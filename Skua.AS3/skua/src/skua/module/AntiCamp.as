package skua.module
{
	import flash.external.ExternalInterface;
	import flash.utils.getTimer;

	/**
	 * Punishes camping (staying in your own team's safe room too long) with
	 * real, server-validated damage, using the game's own native
	 * world.aggroAllMon() (confirmed in World.as: builds the monster-ID list
	 * from monTree entries whose strFrame matches your own world.strFrame,
	 * then sends a real "%xt%zm%aggroMon%" packet) — the exact same call the
	 * official client makes, so the server applies it for real. Confirmed via
	 * the original Skua's AggroAllMonsters option that this always lands on
	 * whoever triggered it, not a remote target — which is exactly what we
	 * want here: each camping player's own client punishes itself.
	 *
	 * Bludrutbrawl's clear-state rule bans camping in your OWN team's safe
	 * room only (Morale0A for Blue, Morale1A for Red), so this only watches
	 * whichever one of those two matches your own team. Team read/gate
	 * mirrors TeamFlagReskin.as exactly (av.dataLeaf.pvpTeam, gated on
	 * bPvP && pvpTeam != null && pvpTeam > -1 — int(pvpTeam)) alone silently
	 * casts null/undefined to 0, which would misread team 0 (Blue) outside
	 * PvP entirely): team 0 = Blue -> Morale0A, team 1 = Red -> Morale1A.
	 *
	 * There's no client-side "un-aggro" — checked every plausible name
	 * (aggro/calm/leash/disengage/flee/resetMon/monTarget/leaveCombat) across
	 * World.as, Game.as, MonsterMC.as, and the original Skua's own option
	 * list; the only exposed call is exitCombat(), which clears YOUR OWN
	 * target/action state, not a monster's aggro onto you. Once a monster is
	 * aggroed the server's own AI keeps attacking on its own until something
	 * natural de-aggroes it — confirmed via testing that even a SINGLE
	 * already-aggroed monster kept landing hits after HP crossed the safety
	 * floor, so this isn't a multi-monster pile-on problem, it's that one
	 * fire-and-forget trigger can chain into several of that one monster's
	 * own attacks with nothing we can do to interrupt them mid-sequence.
	 *
	 * A death from this would be a MONSTER kill, which the server's
	 * match/wave kill-counter doesn't credit as a point (confirmed) — worse,
	 * if the camper was already low from real PvP, this could steal a kill
	 * that would otherwise have gone to whoever was actually fighting them.
	 * Since we can't stop an already-firing sequence, the only lever left is
	 * not starting a new one once HP is already dangerous: this keeps
	 * re-firing aggroAllMon() on an interval the whole time camp conditions
	 * hold, but skips each fire once intHP drops to/below HP_SAFETY_FLOOR,
	 * resuming once it climbs back above that from natural regen. Doesn't
	 * guarantee zero risk from a sequence already in flight when the floor
	 * is crossed — that's the remaining open problem.
	 */
	public class AntiCamp extends Module
	{
		private static const CAMP_THRESHOLD_MS:int = 3000;
		private static const REFIRE_INTERVAL_MS:int = 1500;
		private static const HP_SAFETY_FLOOR:int = 1500;
		private static const BLUE_CELL:String = "Morale0A";
		private static const RED_CELL:String  = "Morale1A";

		private var _lastCell:String = "";
		private var _enteredAtMs:int = 0;
		private var _lastFireMs:int = 0;

		public function AntiCamp() { super("AntiCamp"); }

		override public function onToggle(game:*):void
		{
			_lastCell = "";
			_lastFireMs = 0;
			if (enabled)
			{
				try
				{
					_lastCell = game.world.strFrame;
					_enteredAtMs = getTimer();
				}
				catch (e:Error) {}
			}
		}

		// -1 = not in a gated PvP team (outside PvP, or spectating/no team) —
		// module stays fully inert in that case, same gate TeamFlagReskin uses.
		private function myTeam(game:*):int
		{
			try
			{
				var leaf:* = game.world.myAvatar.dataLeaf;
				if (Boolean(game.world.bPvP) && leaf.pvpTeam != null && leaf.pvpTeam > -1)
					return int(leaf.pvpTeam);
			}
			catch (e:Error) {}
			return -1;
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			try
			{
				var team:int = myTeam(game);
				var watchedCell:String = (team == 0) ? BLUE_CELL : (team == 1 ? RED_CELL : null);

				var cell:String = game.world.strFrame;

				if (cell != _lastCell)
				{
					_lastCell = cell;
					_enteredAtMs = getTimer();
					_lastFireMs = 0;
					return;
				}

				if (watchedCell == null || cell != watchedCell) return;

				var now:int = getTimer();
				if (now - _enteredAtMs < CAMP_THRESHOLD_MS) return;
				if (now - _lastFireMs < REFIRE_INTERVAL_MS) return;

				var hp:int = int(game.world.myAvatar.dataLeaf.intHP);
				if (hp <= HP_SAFETY_FLOOR)
				{
					debug("HP " + hp + " at/under safety floor " + HP_SAFETY_FLOOR + " -> skipping this cycle");
					return;
				}

				_lastFireMs = now;
				game.world.aggroAllMon();
				debug("team " + team + " camping \"" + cell + "\" (hp=" + hp + ") -> aggroAllMon() fired");
			}
			catch (err:Error)
			{
				debug("FAILED: " + err.message);
			}
		}

		private function debug(msg:String):void
		{
			try { ExternalInterface.call("debug", "[AntiCamp] " + msg); }
			catch (e:Error) {}
		}
	}
}
