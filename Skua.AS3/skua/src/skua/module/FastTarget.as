package skua.module
{
	import flash.events.MouseEvent;
	import flash.geom.Rectangle;

	/**
	 * Intercepts MOUSE_DOWN in capture phase and calls world.setTarget() immediately,
	 * bypassing the game's own CLICK-based targeting. The game uses MouseEvent.CLICK
	 * (requires matching MOUSE_DOWN + MOUSE_UP on the same DisplayObject) which fails
	 * when characters animate between the two events. MOUSE_DOWN fires the instant the
	 * button is pressed so there is nothing to mis-match.
	 *
	 * Two matching strategies, tried in order:
	 *
	 *  1. resolveByTarget() walks e.target's ancestor chain for an avatar/monster's
	 *     pMC — the same signal the native game itself uses for its own (slower)
	 *     CLICK-based targeting. Trying this first keeps our instant pick and the
	 *     native pick in agreement: without it, clicking a spot where an enemy
	 *     visually overlaps/stands in front of you would match "self" here (self is
	 *     tested independently of render order) and then get silently overridden by
	 *     the enemy a moment later when the native CLICK fires on mouse-up — visibly
	 *     flip-flopping the target.
	 *
	 *  2. matchesEntity() is a direct geometric shape test, used only as a fallback
	 *     once (1) finds nothing. e.target resolution is binary and fragile — it
	 *     depends on the exact pixel clicked being opaque and mouse-enabled — so a
	 *     click that's visually right on a character can still resolve to nothing.
	 *     It's also the ONLY way to detect a click on your own avatar at all, since
	 *     the game mouse-disables your whole pMC subtree, meaning e.target can never
	 *     resolve into it no matter where you click.
	 *
	 * Both stages reject clicks on the nameplate / PlayerHPBars' HP-MP bar, which
	 * float well above the body and are still children of the same pMC.
	 *
	 * Overlapping avatars/monsters can still flip which one is topmost between the
	 * instant this fires (MOUSE_DOWN) and the moment the game's own native targeting
	 * fires (a real MouseEvent.CLICK, dispatched by the Flash Player itself directly
	 * on the clicked avatar's mcChar/shadow — see AvatarMC/MonsterMC.onClickHandler,
	 * which calls world.setTarget() completely independently of anything done here;
	 * calling stopPropagation() on our own MOUSE_DOWN cannot suppress it). The two
	 * characters' rendered z-order for a given pixel can differ between those two
	 * moments (per-frame depth-sorting by Y-position, animation, etc.), so the
	 * native handler can genuinely pick someone different a few milliseconds later.
	 * Rather than fight that, onLateClick() reasserts whatever WE decided at
	 * MOUSE_DOWN once more, right after — a bubble-phase listener on stage always
	 * fires after one on the clicked object itself, regardless of priority, so this
	 * is guaranteed to run last and win.
	 */
	public class FastTarget extends Module
	{
		private var _game:*;
		private var _pendingTarget:* = null;

		public function FastTarget() { super("FastTarget"); }

		override public function onToggle(game:*):void
		{
			_game = game;
			if (enabled)
			{
				game.stage.addEventListener(MouseEvent.MOUSE_DOWN, onDown, true, 100);
				game.stage.addEventListener(MouseEvent.CLICK, onLateClick, false);
			}
			else
			{
				game.stage.removeEventListener(MouseEvent.MOUSE_DOWN, onDown, true);
				game.stage.removeEventListener(MouseEvent.CLICK, onLateClick, false);
			}
		}

		private function onDown(e:MouseEvent):void
		{
			try
			{
				_pendingTarget = null;
				var myAv:* = _game.world.myAvatar;

				var hit:* = resolveByTarget(e.target);
				if (hit)
				{
					_pendingTarget = hit;
					_game.world.setTarget(hit);
					return;
				}

				// e.target didn't resolve to any (mouse-enabled) avatar/monster —
				// most likely because it's your own avatar, whose pMC is mouse-
				// disabled by the game and so can never be a real e.target.
				//
				// A click landing on the self-portrait panel or the action bar must
				// never register as clicking your OWN avatar here, or the corner
				// self-HUD bars (SelfHud) / skill slots (SkillBarSkin) would count
				// as clicking whatever's underneath that fixed screen position.
				// Scoped to self only — other avatars/monsters are already handled
				// by resolveByTarget() above, or matchesEntity() below on their own
				// real body shape, so this must not gate them too.
				var selfBlockedByUI:Boolean = inBounds(_game.ui.mcPortrait, e.stageX, e.stageY)
					|| (_game.ui.mcInterface && inBounds(_game.ui.mcInterface.actBar, e.stageX, e.stageY));

				if (!selfBlockedByUI && myAv && matchesEntity(myAv, e.stageX, e.stageY))
				{
					_pendingTarget = myAv;

					// Synthesize a real CLICK on your own pMC so the native target
					// UI/state actually refreshes — calling setTarget() alone leaves
					// it stale, since a real MOUSE_DOWN/CLICK never lands there. This
					// bubbles to stage and re-enters onLateClick() synchronously
					// (harmless — _pendingTarget is already myAv at that point).
					var click:MouseEvent = new MouseEvent(MouseEvent.CLICK, true, false,
						e.stageX, e.stageY, myAv.pMC, false, false, false, true, 0);
					myAv.pMC.dispatchEvent(click);
					_game.world.dispatchEvent(click);
					_game.world.setTarget(myAv);
					return;
				}

				// Last resort: e.target missed a genuinely mouse-enabled avatar/
				// monster too (a transparent gap between limbs, etc.) — fall back
				// to the same geometric test so a visually-on-target click never
				// silently does nothing.
				for each (var av:* in _game.world.avatars)
				{
					if (av && !av.isMyAvatar && matchesEntity(av, e.stageX, e.stageY))
					{
						_pendingTarget = av;
						_game.world.setTarget(av);
						return;
					}
				}
				for each (var mon:* in _game.world.monsters)
				{
					if (mon && matchesEntity(mon, e.stageX, e.stageY))
					{
						_pendingTarget = mon;
						_game.world.setTarget(mon);
						return;
					}
				}
			}
			catch (err:Error) {}
		}

		// Runs after the game's own native CLICK-based targeting has already had
		// its say (see class doc) and forces the target back to whatever we
		// decided at MOUSE_DOWN, so overlapping/depth-sorted characters can't
		// silently steal the target out from under our instant pick.
		private function onLateClick(e:MouseEvent):void
		{
			try
			{
				if (_pendingTarget) _game.world.setTarget(_pendingTarget);
			}
			catch (err:Error) {}
			_pendingTarget = null;
		}

		// Walks target's ancestor chain looking for an avatar/monster's pMC — the
		// same resolution the native game's own CLICK-based targeting relies on.
		private function resolveByTarget(target:*):*
		{
			try
			{
				if (isUnderNameplate(target)) return null;

				var obj:* = target;
				while (obj != null && obj != _game.stage)
				{
					for each (var av:* in _game.world.avatars)
					{
						if (av && !av.isMyAvatar && av.pMC && obj === av.pMC)
							return av;
					}
					for each (var mon:* in _game.world.monsters)
					{
						if (mon && mon.pMC && obj === mon.pMC)
							return mon;
					}
					obj = obj.parent;
				}
			}
			catch (err:Error) {}
			return null;
		}

		// True if `target` is a nameplate ("pname") or nested inside one, for any
		// avatar/monster. Walks target's ancestor chain rather than the other way
		// around since pname sits well above pMC's body geometry, not inside it.
		private function isUnderNameplate(target:*):Boolean
		{
			try
			{
				var o:* = target;
				while (o != null)
				{
					for each (var av:* in _game.world.avatars)
					{
						if (av && av.pMC && av.pMC.pname && o === av.pMC.pname) return true;
					}
					for each (var mon:* in _game.world.monsters)
					{
						if (mon && mon.pMC && mon.pMC.pname && o === mon.pMC.pname) return true;
					}
					o = o.parent;
				}
			}
			catch (err:Error) {}
			return false;
		}

		// True if (stageX, stageY) lands on ent's actual rendered body, excluding
		// the nameplate/HP-bar/etc. floating above its head.
		private function matchesEntity(ent:*, stageX:Number, stageY:Number):Boolean
		{
			try
			{
				if (!ent || !ent.pMC) return false;
				var pMC:* = ent.pMC;

				if (pMC.pname)
				{
					var pnameBounds:Rectangle = pMC.pname.getBounds(_game.stage);
					if (stageY <= pnameBounds.bottom) return false;
				}

				return pMC.hitTestPoint(stageX, stageY, true);
			}
			catch (e:Error) {}
			return false;
		}

		private function inBounds(obj:*, stageX:Number, stageY:Number):Boolean
		{
			try
			{
				if (!obj) return false;
				var r:Rectangle = obj.getBounds(_game.stage);
				return r.contains(stageX, stageY);
			}
			catch (e:Error) {}
			return false;
		}
	}
}
