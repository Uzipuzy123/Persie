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
	 * DisableNativeGlow. Also sweeps game.world.map's children (torches,
	 * banners, water, door/portal effects, etc.) — first pass only covered
	 * avatars, missed the map's own decorative animation entirely.
	 *
	 * Deliberately does NOT call stop() on mcChar or game.world.map
	 * themselves: mcChar's own timeline drives the character's Walk/Idle/
	 * Attack pose via gotoAndPlay() (confirmed via decompiled AvatarMC.as),
	 * and the map's own timeline drives room-state switching via
	 * gotoAndPlay(strFrame) (confirmed via decompiled BludRutBrawl
	 * MainTimeline) — stopping either would break movement or room
	 * transitions/spawns entirely. Only their CHILDREN are swept. Calling
	 * stop() on a child is safe even if AQW's own logic repositions/regotos
	 * that child every frame — stop() only halts a clip's own autonomous
	 * frame-advancement, it doesn't block external gotoAndStop(n) calls from
	 * the parent controller. It only actually removes decorative loops that
	 * play on their own with no external control (rotating gems, pulsing
	 * sparks, idle sway, flickering torches, waving banners).
	 *
	 * Runs every frame rather than once-and-cache, same reasoning as
	 * DisableNativeGlow: equipped parts (and the loaded map) can change at
	 * any time.
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

			try
			{
				var map:DisplayObjectContainer = game.world.map as DisplayObjectContainer;
				if (map)
				{
					for (var mi:int = 0; mi < map.numChildren; mi++)
						freeze(map.getChildAt(mi));
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

			try
			{
				var map:DisplayObjectContainer = game.world.map as DisplayObjectContainer;
				if (map)
				{
					for (var mi:int = 0; mi < map.numChildren; mi++)
						unfreeze(map.getChildAt(mi));
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
