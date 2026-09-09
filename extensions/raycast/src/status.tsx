import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { useCallback, useEffect, useState } from "react";
import { control, MODES, remainingLabel, reportError, Status } from "./client";
import StartSession from "./start-session";

export default function SessionStatus() {
  const [status, setStatus] = useState<Status>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>();
  const refresh = useCallback(async (allowLaunch = true) => {
    try {
      setStatus(await control({ command: "status" }, allowLaunch));
      setError(undefined);
    } catch (error) {
      setError(error instanceof Error ? error.message : String(error));
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    refresh();
    const timer = setInterval(() => refresh(false), 5000);
    return () => clearInterval(timer);
  }, [refresh]);
  const actions = (
    <ActionPanel>
      <Action.Push title="Start Session" target={<StartSession />} />
      <Action
        title="Stop Session"
        icon={Icon.Stop}
        onAction={async () => {
          try {
            setStatus(await control({ command: "stop" }));
          } catch (error) {
            await reportError(error);
          }
        }}
      />
      <Action
        title="Refresh Status"
        icon={Icon.ArrowClockwise}
        onAction={() => refresh()}
      />
      <Action
        title="Open Caffeinator"
        icon={Icon.AppWindow}
        onAction={async () => {
          try {
            await control({ command: "show" });
          } catch (error) {
            await reportError(error);
          }
        }}
      />
    </ActionPanel>
  );
  return (
    <List
      isLoading={loading}
      searchBarPlaceholder="Session status"
      navigationTitle="Caffeinator"
      actions={actions}
    >
      {error ? (
        <List.EmptyView
          title="Could not connect"
          description={error}
          actions={actions}
        />
      ) : (
        status && (
          <>
            <List.Item
              icon={
                status.recovery_required
                  ? Icon.Warning
                  : status.is_active
                    ? Icon.Bolt
                    : Icon.Moon
              }
              title={
                status.recovery_required
                  ? "Sleep restoration required"
                  : status.is_active
                    ? "Your Mac is staying awake"
                    : "Ready for your next session"
              }
              subtitle={status.busy ? "An operation is in progress" : undefined}
              actions={actions}
            />
            <List.Section
              title={status.is_active ? "Current session" : "Saved defaults"}
            >
              <List.Item
                icon={Icon.Gear}
                title="Mode"
                accessories={[
                  { text: MODES[status.mode ?? status.selected_mode] },
                ]}
                actions={actions}
              />
              <List.Item
                icon={Icon.Clock}
                title={status.is_active ? "Time remaining" : "Duration"}
                accessories={[
                  {
                    text: remainingLabel(
                      status.is_active
                        ? status.remaining_seconds
                        : status.selected_duration,
                    ),
                  },
                ]}
                actions={actions}
              />
              {status.error && (
                <List.Item
                  icon={Icon.Warning}
                  title={status.error}
                  actions={actions}
                />
              )}
            </List.Section>
          </>
        )
      )}
    </List>
  );
}
