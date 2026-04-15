# shellcheck shell=bash
# Wait for PipeWire to be ready
sleep 3

echo "Playing silence to default audio sink to prevent amplifier power cycling"

# Play silence forever using pacat (PulseAudio compatible, works with PipeWire)
# Reads raw zeros from /dev/zero, interprets as 48kHz stereo 16-bit audio
# Volume set to 1% (0.01) which is inaudible but keeps the DAC active
exec pacat --playback \
  --rate=48000 \
  --channels=2 \
  --format=s16le \
  --volume=655 \
  --latency-msec=1000 \
  /dev/zero
