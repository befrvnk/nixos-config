package cleanup

import "os/exec"

func DetectStatus() Status {
	return Status{
		AndroidStudioRunning: processMatches("Android Studio.*\\.app/Contents/MacOS/studio"),
		GradleRunning:        processMatches("org\\.gradle\\.launcher\\.daemon\\.bootstrap\\.GradleDaemon"),
	}
}

func processMatches(pattern string) bool {
	return exec.Command("/usr/bin/pgrep", "-f", pattern).Run() == nil
}
