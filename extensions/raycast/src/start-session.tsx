import { Action, ActionPanel, Form, showHUD } from "@raycast/api";
import { useEffect, useState } from "react";
import { control, MODES, Mode, reportError } from "./client";

export default function StartSession() {
  const [loading, setLoading] = useState(true);
  const [mode, setMode] = useState<Mode>("NoIdleSleep");
  const [duration, setDuration] = useState("3600");
  const [customMinutes, setCustomMinutes] = useState("60");
  const [error, setError] = useState<string>();
  useEffect(() => {
    control({ command: "status" })
      .then((status) => {
        setMode(status.selected_mode);
        const seconds = status.selected_duration;
        if (seconds === null) setDuration("indefinite");
        else if ([1800, 3600, 7200, 14400].includes(seconds))
          setDuration(String(seconds));
        else {
          setDuration("custom");
          setCustomMinutes(String(Math.ceil(seconds / 60)));
        }
      })
      .catch(reportError)
      .finally(() => setLoading(false));
  }, []);
  async function submit() {
    const seconds =
      duration === "indefinite"
        ? null
        : duration === "custom"
          ? Number(customMinutes) * 60
          : Number(duration);
    if (
      seconds !== null &&
      (!Number.isInteger(seconds) || seconds < 60 || seconds > 604800)
    ) {
      setError("Enter a duration from 1 to 10,080 minutes (7 days).");
      return;
    }
    setLoading(true);
    try {
      await control({ command: "start", mode, duration_secs: seconds });
      await showHUD(`Session started · ${MODES[mode]}`);
    } catch (error) {
      await reportError(error);
    } finally {
      setLoading(false);
    }
  }
  return (
    <Form
      isLoading={loading}
      navigationTitle="Start a Caffeinator Session"
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Start Session"
            onSubmit={() => {
              if (!loading) submit();
            }}
          />
        </ActionPanel>
      }
    >
      <Form.Dropdown
        id="mode"
        title="Mode"
        value={mode}
        onChange={(value) => setMode(value as Mode)}
      >
        {Object.entries(MODES).map(([value, title]) => (
          <Form.Dropdown.Item key={value} value={value} title={title} />
        ))}
      </Form.Dropdown>
      <Form.Dropdown
        id="duration"
        title="Duration"
        value={duration}
        onChange={(value) => {
          setDuration(value);
          setError(undefined);
        }}
      >
        <Form.Dropdown.Item value="1800" title="30 minutes" />
        <Form.Dropdown.Item value="3600" title="1 hour" />
        <Form.Dropdown.Item value="7200" title="2 hours" />
        <Form.Dropdown.Item value="14400" title="4 hours" />
        <Form.Dropdown.Item value="indefinite" title="Until stopped" />
        <Form.Dropdown.Item value="custom" title="Custom duration" />
      </Form.Dropdown>
      {duration === "custom" && (
        <Form.TextField
          id="minutes"
          title="Minutes"
          value={customMinutes}
          error={error}
          onChange={(value) => {
            setCustomMinutes(value);
            setError(undefined);
          }}
          placeholder="60"
        />
      )}
      <Form.Separator />
      <Form.Description
        title={mode === "ServerMode" ? "Administrator access" : "Your session"}
        text={
          mode === "ServerMode"
            ? "macOS will ask for authorization to disable lid-close sleep. Stopping restores your original setting and may ask again."
            : mode === "NoDisplaySleep"
              ? "Your Mac and its display stay awake. Normal sleep settings are preserved."
              : mode === "NoIdleSleep"
                ? "Your Mac stays awake while the display follows its normal sleep settings."
                : "macOS manages this assertion according to the selected network or background workload."
        }
      />
    </Form>
  );
}
