package falconstats

import (
	"strings"
	"testing"
)

func TestParseAndDiff(t *testing.T) {
	plist := `<?xml version="1.0"?><plist><dict>
<key>queue</key><dict><key>total_queued</key><integer>120</integer><key>max_queue_depth</key><integer>30</integer></dict>
<key>smcache</key><dict><key>read_hits</key><integer>80</integer><key>read_misses</key><integer>4</integer></dict>
<key>EndpointSecurity</key><dict><key>authExecCount</key><integer>12</integer></dict>
<key>StaticAnalysis</key><dict><key>requests</key><integer>7</integer><key>failedFileTooLarge</key><integer>2</integer></dict>
<key>Communications</key><dict><key>Communication</key><dict><key>Event Sums</key><dict><key>Sent</key><array><string>1</string><string>2</string><string>9</string></array></dict><key>Events Sent</key><dict><key>JavaClassFileWrittenMacV5</key><array><string>1</string><string>2</string><string>5</string></array><key>JarFileWrittenMacV6</key><array><string>0</string><string>0</string><string>3</string></array><key>ZipFileWrittenMacV5</key><array><string>0</string><string>0</string><string>4</string></array></dict></dict></dict>
</dict></plist>`
	counters, err := Parse(strings.NewReader(plist))
	if err != nil {
		t.Fatal(err)
	}
	if counters.QueueTotal != 120 || counters.JavaClassWritten != 5 || counters.EventsSent != 9 {
		t.Fatalf("counters = %#v", counters)
	}
	delta := Diff(Counters{QueueTotal: 100, CacheReadHits: 60, JavaClassWritten: 2}, counters)
	if delta.QueueProcessed != 20 || delta.CacheReadHits != 20 || delta.JavaClassWrittenNet != 3 {
		t.Fatalf("delta = %#v", delta)
	}
}
