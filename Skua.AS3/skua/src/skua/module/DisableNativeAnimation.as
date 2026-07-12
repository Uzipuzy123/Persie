package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.MovieClip;

	/**
	 * Freezes the internal animation of every part of every avatar's mcChar
	 * body tree — weapon, weaponOff, weaponFist, weaponFistOff, cape, robe,
	 * backrobe, backhair, pvpFlag, plus every body segment (head/chest/hip/
	 * shoulders/thighs/shins/hands/feet) — same full-tree scope as
	 * DisableNativeGlow.
	 *
	 * Deliberately does NOT touch game.world.map or any of its children.
	 * An earlier version also swept map's children to freeze decorative loops
	 * (torches, banners, gems) — bludrutbrawl (and likely other multi-room
	 * maps) turned out to drive room placement through nested child clips on
	 * unlabeled frame numbers, not just the top-level map timeline. Freezing
	 * one of those mid-transition parked it on whatever frame it froze at,
	 * which the game then treated as "arrived" — landing the player in the
	 * wrong room on join. A frame-label check (skip clips with named labels)
	 * was tried and still didn't stop it, meaning the room logic isn't even
	 * label-driven on every map. Given map structure isn't reliably
	 * distinguishable between "decoration" and "room state" from the outside,
	 * this only touches avatars now — safe because avatar body parts are
	 * never involved in room/map transition logic.
	 *
	 * Deliberately does NOT call stop() on mcChar itself: its own timeline
	 * drives the character's Walk/Idle/Attack pose via gotoAndPlay()
	 * (confirmed via decompiled AvatarMC.as) — stopping it would break
	 * movement animation entirely. Only its CHILDREN are swept. Calling
	 * stop() on a child is safe even if AQW's own logic repositions/regotos
	 * that child every frame — stop() only halts a clip's own autonomous
	 * frame-advancement, it doesn't block external gotoAndStop(n) calls from
	 * the parent controller. It only actually removes decorative loops that
	 * play on their own with no external control (rotating gems, pulsing
	 * sparks, idle sway, flickering torches, waving banners, cape/robe cloth
	 * sway).
	 *
	 * Runs every frame rather than once-and-cache, same reasoning as
	 * DisableNativeGlow: equipped parts can change at any time.
	 */
	public class DisableNativeAnimation extends Module
	{
		public function DisableNativeAnimation() { super("DisableNativeAnimation"); }

		override public function onToggle(game:*):void
		{
			if (!enabled) restoreAll(game);
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			try
			{
				for (var aid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[aid];
					if (!av || !av.pMC || !av.pMC.mcChar) continue;
					var mcChar:DisplayObjectContainer = av.pMC.mcChar as DisplayObjectContainer;
					if (!mcChar) continue;
					for (var i:int = 0; i < mcChar.numChildren; i++)
						freeze(mcChar.getChildAt(i));
				}
			}
			catch (e:Error) {}
		}

		private function freeze(obj:DisplayObject):void
		{
			try
			{
				if (obj is MovieClip) MovieClip(obj).stop();
				if (obj is DisplayObjectContainer)
				{
					var doc:DisplayObjectContainer = DisplayObjectContainer(obj);
					for (var i:int = 0; i < doc.numChildren; i++)
						freeze(doc.getChildAt(i));
				}
			}
			catch (e:Error) {}
		}

		private function restoreAll(game:*):void
		{
			try
			{
				for (var aid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[aid];
					if (!av || !av.pMC || !av.pMC.mcChar) continue;
					var mcChar:DisplayObjectContainer = av.pMC.mcChar as DisplayObjectContainer;
					if (!mcChar) continue;
					for (var i:int = 0; i < mcChar.numChildren; i++)
						unfreeze(mcChar.getChildAt(i));
				}
			}
			catch (e:Error) {}
		}

		private function unfreeze(obj:DisplayObject):void
		{
			try
			{
				if (obj is MovieClip) MovieClip(obj).play();
				if (obj is DisplayObjectContainer)
				{
					var doc:DisplayObjectContainer = DisplayObjectContainer(obj);
					for (var i:int = 0; i < doc.numChildren; i++)
						unfreeze(doc.getChildAt(i));
				}
			}
			catch (e:Error) {}
		}
	}
}
