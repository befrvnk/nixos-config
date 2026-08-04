package falconstats

import (
	"encoding/xml"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

type Counters struct {
	QueueTotal        int64 `json:"queue_total"`
	QueueMaximumDepth int64 `json:"queue_maximum_depth"`
	CacheReadHits     int64 `json:"cache_read_hits"`
	CacheReadMisses   int64 `json:"cache_read_misses"`
	AuthExec          int64 `json:"endpoint_security_auth_exec"`
	StaticRequests    int64 `json:"static_analysis_requests"`
	StaticTooLarge    int64 `json:"static_analysis_too_large"`
	JavaClassWritten  int64 `json:"java_class_written_rolling_1h"`
	JarWritten        int64 `json:"jar_written_rolling_1h"`
	ZipWritten        int64 `json:"zip_written_rolling_1h"`
	EventsSent        int64 `json:"events_sent_rolling_1h"`
}

type Delta struct {
	QueueProcessed            int64 `json:"queue_processed"`
	QueueMaximumDepthIncrease int64 `json:"queue_maximum_depth_increase"`
	CacheReadHits             int64 `json:"cache_read_hits"`
	CacheReadMisses           int64 `json:"cache_read_misses"`
	AuthExec                  int64 `json:"endpoint_security_auth_exec"`
	StaticRequests            int64 `json:"static_analysis_requests"`
	StaticTooLarge            int64 `json:"static_analysis_too_large"`
	JavaClassWrittenNet       int64 `json:"java_class_written_rolling_1h_net"`
	JarWrittenNet             int64 `json:"jar_written_rolling_1h_net"`
	ZipWrittenNet             int64 `json:"zip_written_rolling_1h_net"`
	EventsSentNet             int64 `json:"events_sent_rolling_1h_net"`
}

func DiffFiles(startPath, endPath string) (Delta, error) {
	start, err := ParseFile(startPath)
	if err != nil {
		return Delta{}, fmt.Errorf("parse start stats: %w", err)
	}
	end, err := ParseFile(endPath)
	if err != nil {
		return Delta{}, fmt.Errorf("parse end stats: %w", err)
	}
	return Diff(start, end), nil
}

func Diff(start, end Counters) Delta {
	return Delta{
		QueueProcessed:            nonNegative(end.QueueTotal - start.QueueTotal),
		QueueMaximumDepthIncrease: nonNegative(end.QueueMaximumDepth - start.QueueMaximumDepth),
		CacheReadHits:             nonNegative(end.CacheReadHits - start.CacheReadHits),
		CacheReadMisses:           nonNegative(end.CacheReadMisses - start.CacheReadMisses),
		AuthExec:                  nonNegative(end.AuthExec - start.AuthExec),
		StaticRequests:            nonNegative(end.StaticRequests - start.StaticRequests),
		StaticTooLarge:            nonNegative(end.StaticTooLarge - start.StaticTooLarge),
		JavaClassWrittenNet:       end.JavaClassWritten - start.JavaClassWritten,
		JarWrittenNet:             end.JarWritten - start.JarWritten,
		ZipWrittenNet:             end.ZipWritten - start.ZipWritten,
		EventsSentNet:             end.EventsSent - start.EventsSent,
	}
}

func ParseFile(path string) (Counters, error) {
	file, err := os.Open(path)
	if err != nil {
		return Counters{}, err
	}
	defer file.Close()
	return Parse(file)
}

func Parse(input io.Reader) (Counters, error) {
	value, err := parsePlist(input)
	if err != nil {
		return Counters{}, err
	}
	return Counters{
		QueueTotal:        integerAt(value, "queue", "total_queued"),
		QueueMaximumDepth: integerAt(value, "queue", "max_queue_depth"),
		CacheReadHits:     integerAt(value, "smcache", "read_hits"),
		CacheReadMisses:   integerAt(value, "smcache", "read_misses"),
		AuthExec:          integerAt(value, "EndpointSecurity", "authExecCount"),
		StaticRequests:    integerAt(value, "StaticAnalysis", "requests"),
		StaticTooLarge:    integerAt(value, "StaticAnalysis", "failedFileTooLarge"),
		JavaClassWritten:  arrayIntegerAt(value, 2, "Communications", "Communication", "Events Sent", "JavaClassFileWrittenMacV5"),
		JarWritten:        arrayIntegerAt(value, 2, "Communications", "Communication", "Events Sent", "JarFileWrittenMacV6"),
		ZipWritten:        arrayIntegerAt(value, 2, "Communications", "Communication", "Events Sent", "ZipFileWrittenMacV5"),
		EventsSent:        arrayIntegerAt(value, 2, "Communications", "Communication", "Event Sums", "Sent"),
	}, nil
}

func parsePlist(input io.Reader) (map[string]any, error) {
	decoder := xml.NewDecoder(input)
	for {
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		start, ok := token.(xml.StartElement)
		if !ok || start.Name.Local != "dict" {
			continue
		}
		value, err := parseDict(decoder)
		if err != nil {
			return nil, err
		}
		return value, nil
	}
}

func parseDict(decoder *xml.Decoder) (map[string]any, error) {
	result := make(map[string]any)
	key := ""
	for {
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		switch value := token.(type) {
		case xml.EndElement:
			if value.Name.Local == "dict" {
				return result, nil
			}
		case xml.StartElement:
			if value.Name.Local == "key" {
				if err := decoder.DecodeElement(&key, &value); err != nil {
					return nil, err
				}
				continue
			}
			parsed, err := parseValue(decoder, value)
			if err != nil {
				return nil, err
			}
			if key != "" {
				result[key] = parsed
				key = ""
			}
		}
	}
}

func parseValue(decoder *xml.Decoder, start xml.StartElement) (any, error) {
	switch start.Name.Local {
	case "dict":
		return parseDict(decoder)
	case "array":
		var result []any
		for {
			token, err := decoder.Token()
			if err != nil {
				return nil, err
			}
			switch value := token.(type) {
			case xml.EndElement:
				if value.Name.Local == "array" {
					return result, nil
				}
			case xml.StartElement:
				parsed, err := parseValue(decoder, value)
				if err != nil {
					return nil, err
				}
				result = append(result, parsed)
			}
		}
	case "true":
		if err := decoder.Skip(); err != nil {
			return nil, err
		}
		return true, nil
	case "false":
		if err := decoder.Skip(); err != nil {
			return nil, err
		}
		return false, nil
	default:
		var text string
		if err := decoder.DecodeElement(&text, &start); err != nil {
			return nil, err
		}
		return strings.TrimSpace(text), nil
	}
}

func integerAt(root map[string]any, path ...string) int64 {
	value := any(root)
	for _, component := range path {
		object, ok := value.(map[string]any)
		if !ok {
			return 0
		}
		value = object[component]
	}
	return toInteger(value)
}

func arrayIntegerAt(root map[string]any, index int, path ...string) int64 {
	value := any(root)
	for _, component := range path {
		object, ok := value.(map[string]any)
		if !ok {
			return 0
		}
		value = object[component]
	}
	values, ok := value.([]any)
	if !ok || index < 0 || index >= len(values) {
		return 0
	}
	return toInteger(values[index])
}

func toInteger(value any) int64 {
	switch value := value.(type) {
	case int64:
		return value
	case string:
		result, _ := strconv.ParseInt(value, 10, 64)
		return result
	default:
		return 0
	}
}

func nonNegative(value int64) int64 {
	if value < 0 {
		return 0
	}
	return value
}
