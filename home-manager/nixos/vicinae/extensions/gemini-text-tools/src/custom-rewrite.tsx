import { useEffect, useState } from "react";
import { Detail } from "@vicinae/api";
import { getPreferences } from "./lib/preferences.js";
import { readSourceText } from "./lib/text.js";
import { CustomRewriteForm } from "./components/CustomRewriteForm.js";

export default function CustomRewriteCommand() {
  const preferences = getPreferences();
  const [initialText, setInitialText] = useState<string>("");
  const [isLoading, setIsLoading] = useState<boolean>(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const text = await readSourceText(preferences.source);
        if (!cancelled) {
          setInitialText(text);
        }
      } catch {
        if (!cancelled) {
          setInitialText("");
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    }

    void load();

    return () => {
      cancelled = true;
    };
  }, [preferences.source]);

  if (isLoading) {
    return <Detail markdown="# Loading current text source…" />;
  }

  return <CustomRewriteForm initialText={initialText} />;
}
