#!/usr/bin/env bash
# Get list of apps currently playing audio
# Used by display-details.sh for showing what's keeping screen on

# Get audio streams via PipeWire (pw-dump + jq)
APPS=$(pw-dump 2>/dev/null | jq -r '.[] | select(.info.props."media.class" == "Stream/Output/Audio" and .info.props."application.name" != null) | .info.props."application.name"' 2>/dev/null | sort -u | head -5)

if [[ -n "$APPS" ]]; then
    echo "$APPS"
else
    echo "None"
fi
