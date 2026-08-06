/**
 * Keep Herdr from treating Pi as idle while detached work is still running.
 *
 * Herdr's managed Pi integration exposes a cooperative `herdr:blocked` lease
 * for adjacent extensions. Background terminals share one lease regardless of
 * how many processes are running, so overlapping terminals cannot unbalance
 * Herdr's blocker counter.
 */

export const HERDR_BACKGROUND_LABEL = "Background terminal running";

export interface HerdrBlockedEvent {
  readonly active: boolean;
  readonly label?: string;
}

export function createHerdrBackgroundHold(
  emit: (event: HerdrBlockedEvent) => void,
) {
  let running = 0;
  let foregroundActive = false;
  let held = false;

  const sync = () => {
    const nextHeld = running > 0 && !foregroundActive;
    if (nextHeld === held) return;

    held = nextHeld;
    emit({
      active: held,
      label: held ? HERDR_BACKGROUND_LABEL : undefined,
    });
  };

  return {
    updateRunning(nextRunning: number) {
      running = nextRunning;
      sync();
    },
    setForegroundActive(active: boolean) {
      foregroundActive = active;
      sync();
    },
  };
}
