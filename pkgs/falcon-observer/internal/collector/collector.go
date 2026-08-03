package collector

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"time"
)

type Config struct {
	Enabled              bool
	FalconctlPath        string
	FSUsagePath          string
	PowermetricsPath     string
	SamplePath           string
	MaximumDuration      time.Duration
	PowermetricsInterval time.Duration
	MaximumFileBytes     int64
}

type Session struct {
	config   Config
	dir      string
	mu       sync.Mutex
	commands []*managedCommand
	sampled  bool
}

type managedCommand struct {
	name        string
	command     *exec.Cmd
	done        chan error
	outputPaths []string
	stopped     bool
}

func Start(config Config, dir string) (*Session, error) {
	session := &Session{config: config, dir: dir}
	if !config.Enabled {
		return session, nil
	}

	var failures []error
	// Start the continuous collectors first so Falcon stats collection cannot
	// make us miss the beginning of a short Gradle build.
	if err := session.startFSUsage(); err != nil {
		failures = append(failures, err)
	}
	if err := session.startPowermetrics(); err != nil {
		failures = append(failures, err)
	}
	if err := session.writeFalconStats("falcon-stats-start.plist"); err != nil {
		failures = append(failures, err)
	}
	return session, errors.Join(failures...)
}

func (session *Session) MaybeSampleFalcon(pid int) error {
	session.mu.Lock()
	defer session.mu.Unlock()
	if !session.config.Enabled || session.sampled || pid <= 0 {
		return nil
	}
	output := filepath.Join(session.dir, "falcon-sample.txt")
	logPath := filepath.Join(session.dir, "falcon-sample-command.log")
	managed, err := startCommand(
		"sample",
		session.config.SamplePath,
		[]string{strconv.Itoa(pid), "10", "-file", output},
		logPath,
	)
	if err != nil {
		return err
	}
	managed.outputPaths = append(managed.outputPaths, output)
	session.commands = append(session.commands, managed)
	session.sampled = true
	return nil
}

func (session *Session) EnforceFileLimits() []error {
	if session.config.MaximumFileBytes <= 0 {
		return nil
	}
	session.mu.Lock()
	defer session.mu.Unlock()
	var failures []error
	for _, command := range session.commands {
		if command.stopped {
			continue
		}
		for _, path := range command.outputPaths {
			info, err := os.Stat(path)
			if err != nil {
				if !os.IsNotExist(err) {
					failures = append(failures, fmt.Errorf("stat %s output: %w", command.name, err))
				}
				continue
			}
			if info.Size() >= session.config.MaximumFileBytes {
				if err := stopCommand(command); err != nil {
					failures = append(failures, fmt.Errorf("stop %s at file limit: %w", command.name, err))
				} else {
					failures = append(failures, fmt.Errorf("%s stopped after reaching the %d-byte file limit", command.name, session.config.MaximumFileBytes))
				}
				break
			}
		}
	}
	return failures
}

func (session *Session) Stop() error {
	session.mu.Lock()
	commands := append([]*managedCommand(nil), session.commands...)
	session.mu.Unlock()

	var failures []error
	for _, command := range commands {
		if err := stopCommand(command); err != nil {
			failures = append(failures, fmt.Errorf("stop %s: %w", command.name, err))
		}
	}
	if session.config.Enabled {
		if err := session.writeFalconStats("falcon-stats-end.plist"); err != nil {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}

func (session *Session) startFSUsage() error {
	seconds := int(session.config.MaximumDuration.Round(time.Second) / time.Second)
	if seconds < 1 {
		seconds = 2700
	}
	output := filepath.Join(session.dir, "falcon-fs-usage.log")
	managed, err := startCommand(
		"fs_usage",
		session.config.FSUsagePath,
		[]string{"-w", "-f", "filesys", "-t", strconv.Itoa(seconds), "com.crowdstrike.falcon.Agent"},
		output,
	)
	if err != nil {
		return fmt.Errorf("start fs_usage: %w", err)
	}
	managed.outputPaths = []string{output}
	session.commands = append(session.commands, managed)
	return nil
}

func (session *Session) startPowermetrics() error {
	output := filepath.Join(session.dir, "powermetrics.txt")
	logPath := filepath.Join(session.dir, "powermetrics-command.log")
	milliseconds := session.config.PowermetricsInterval.Milliseconds()
	if milliseconds < 1000 {
		milliseconds = 2000
	}
	managed, err := startCommand(
		"powermetrics",
		session.config.PowermetricsPath,
		[]string{
			"--sample-rate", strconv.FormatInt(milliseconds, 10),
			"--sample-count", "-1",
			"--samplers", "tasks,disk,thermal,cpu_power",
			"--show-process-io",
			"--show-process-energy",
			"--show-process-samp-norm",
			"--show-usage-summary",
			"--output-file", output,
		},
		logPath,
	)
	if err != nil {
		return fmt.Errorf("start powermetrics: %w", err)
	}
	managed.outputPaths = []string{output, logPath}
	session.commands = append(session.commands, managed)
	return nil
}

func (session *Session) writeFalconStats(name string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, session.config.FalconctlPath, "stats", "--plist")
	output, err := command.CombinedOutput()
	if writeErr := os.WriteFile(filepath.Join(session.dir, name), output, 0o600); writeErr != nil {
		return fmt.Errorf("write %s: %w", name, writeErr)
	}
	if err != nil {
		return fmt.Errorf("collect %s: %w", name, err)
	}
	return nil
}

func startCommand(name, path string, arguments []string, logPath string) (*managedCommand, error) {
	output, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return nil, err
	}
	command := exec.Command(path, arguments...)
	command.Stdout = output
	command.Stderr = output
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := command.Start(); err != nil {
		output.Close()
		return nil, err
	}
	managed := &managedCommand{
		name:        name,
		command:     command,
		done:        make(chan error, 1),
		outputPaths: []string{logPath},
	}
	go func() {
		err := command.Wait()
		output.Close()
		managed.done <- err
		close(managed.done)
	}()
	return managed, nil
}

func stopCommand(command *managedCommand) error {
	if command.stopped {
		return nil
	}
	command.stopped = true
	select {
	case err := <-command.done:
		if isExpectedExit(err) {
			return nil
		}
		return err
	default:
	}

	pid := command.command.Process.Pid
	_ = syscall.Kill(-pid, syscall.SIGINT)
	select {
	case err := <-command.done:
		if isExpectedExit(err) {
			return nil
		}
		return err
	case <-time.After(5 * time.Second):
		_ = syscall.Kill(-pid, syscall.SIGKILL)
		err := <-command.done
		if isExpectedExit(err) {
			return nil
		}
		return err
	}
}

func isExpectedExit(err error) bool {
	if err == nil {
		return true
	}
	var exitError *exec.ExitError
	if !errors.As(err, &exitError) {
		return false
	}
	status, ok := exitError.Sys().(syscall.WaitStatus)
	if !ok || !status.Signaled() {
		return false
	}
	signal := status.Signal()
	return signal == syscall.SIGINT || signal == syscall.SIGTERM || signal == syscall.SIGKILL
}
