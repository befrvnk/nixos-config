final: prev: {
  claude-code = prev.claude-code.overrideAttrs (old: {
    meta = (old.meta or { }) // {
      mainProgram = "claude";
    };
  });
}
