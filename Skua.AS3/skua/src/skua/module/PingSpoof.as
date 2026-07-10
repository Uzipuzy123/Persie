package skua.module
{
	// Purely visual — shaves an offset (plus small jitter, so it isn't the
	// exact same number every single time) off the displayed ping in the
	// options menu. Never touches real network timing.
	//
	// The game only re-pings the server when the Options menu is (re)opened
	// (mcOption.Init() -> sendXtMessage("zm","hi",...)) — while the menu
	// stays open it's one static number, not a live continuous readout. So
	// this reacts purely to that close/reopen event (detected as mcO.latency
	// changing to a new real value) rather than running its own timer —
	// matches how a real player actually checks ping: open, read, close,
	// reopen, read again.
	public class PingSpoof extends Module
	{
		private static const JITTER_MS:int = 3; // final offset varies +/- this much per reopen

		private var _offsetMs:int = 10;
		private var _lastSeenRaw:Number = NaN;

		public function PingSpoof() { super("PingSpoof"); }

		public function setOffset(ms:int):void { _offsetMs = ms; }

		override public function onToggle(game:*):void
		{
			// Fresh start whenever this is (re)enabled, so it always reacts
			// to the next real reopen rather than an old stale comparison.
			_lastSeenRaw = NaN;
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			try
			{
				var mcO:* = game.mcO;
				if (!mcO) return;
				var raw:Number = mcO.latency;
				if (isNaN(raw)) return;

				// mcOption.Init() sets latency to Date.getTime() (a huge
				// epoch timestamp, 13+ digits) at the moment the menu opens,
				// and it stays that way for however many frames it takes the
				// server's "hi" response to actually land and convert it
				// into a real small ping value. Grabbing that transient
				// timestamp and casting it to int() overflows AS3's 32-bit
				// int, producing garbage (the "1 and 8 million" glitch) — no
				// real ping is ever remotely this large, so just wait.
				if (raw <= 0 || raw > 5000) return;

				// Only act when the game hands us a genuinely new real
				// reading (menu closed and reopened, or switched servers
				// and reopened) — otherwise we'd keep subtracting from our
				// own already-faked value every single frame.
				if (raw === _lastSeenRaw) return;

				var jitter:int = Math.floor(Math.random() * (JITTER_MS * 2 + 1)) - JITTER_MS;
				var shown:int = int(raw) - _offsetMs + jitter;
				if (shown < 1) shown = 1;

				mcO.latency = shown;
				_lastSeenRaw = shown; // matches what we just wrote, so this
				                      // patch doesn't re-trigger itself next frame

				// Re-render through the game's own method so the color
				// threshold (green/yellow/red) stays consistent with the
				// faked number instead of only patching the text string.
				if (mcO.updateLatency is Function)
					mcO.updateLatency();
			}
			catch (e:Error) {}
		}
	}
}
