package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.utils.Dictionary;

	/**
	 * Strips AQW's own native glow/aura effects (nothing to do with any Skua
	 * feature) from every part of every avatar — the ENTIRE mcChar body tree
	 * (weapon, weaponOff, weaponFist, weaponFistOff, shield, cape, robe,
	 * backrobe, backhair, and every body segment: head/chest/hip/shoulders/
	 * thighs/shins/hands/feet), not just held equipment. First attempt only
	 * covered the weapon slots; "everything you can possibly strip it from"
	 * meant the whole body, so this sweeps recursively from mcChar itself
	 * instead of a curated slot list.
	 *
	 * Covers both possible implementations, since which one any given piece
	 * actually uses hasn't been confirmed live: a Flash GlowFilter (stripped
	 * via .filters) and a baked animated glow/sparkle child clip (hidden via
	 * name match, since a filter-only strip wouldn't touch actual drawn
	 * vector art).
	 *
	 * Runs every frame rather than once-and-cache: unlike a shadow, an
	 * avatar's equipment/weapon can change at any time (loadout/skill
	 * swaps), so the tree needs re-checking continuously, not just once.
	 *
	 * Known interaction: if TeamFlagReskin's custom flag icon is also
	 * active, this will also strip the glow WE intentionally added to that
	 * icon, since it's added as a child of the same mcChar. Not worth
	 * special-casing for now — the two features aren't likely to be wanted
	 * together anyway.
	 */
	public class DisableNativeGlow extends Module
	{
		private static const EMPTY:Array = [];
		private static const NAME_HINTS:Array = ["glow", "shine", "sparkle", "aura", "fx"];

		// Weak-keyed: object -> saved original filters Array, for restore.
		private var _filterStore:Dictionary = new Dictionary(true);
		// Weak-keyed: object -> true, for restoring .visible on disable.
		private var _hidden:Dictionary = new Dictionary(true);

		public function DisableNativeGlow() { super("DisableNativeGlow"); }

		override public function onToggle(game:*):void
		{
			if (!enabled) restoreAll();
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
					strip(av.pMC.mcChar as DisplayObject);
				}
			}
			catch (e:Error) {}
		}

		private function strip(obj:DisplayObject):void
		{
			try
			{
				if (obj.filters && obj.filters.length > 0)
				{
					if (_filterStore[obj] === undefined) _filterStore[obj] = obj.filters;
					obj.filters = EMPTY;
				}

				var n:String = obj.name ? obj.name.toLowerCase() : "";
				var isGlowNamed:Boolean = false;
				for each (var hint:String in NAME_HINTS)
				{
					if (n.indexOf(hint) != -1) { isGlowNamed = true; break; }
				}
				if (isGlowNamed && obj.visible)
				{
					_hidden[obj] = true;
					obj.visible = false;
				}

				if (obj is DisplayObjectContainer)
				{
					var doc:DisplayObjectContainer = DisplayObjectContainer(obj);
					for (var i:int = 0; i < doc.numChildren; i++)
						strip(doc.getChildAt(i));
				}
			}
			catch (e:Error) {}
		}

		private function restoreAll():void
		{
			for (var fKey:* in _filterStore)
			{
				try { DisplayObject(fKey).filters = _filterStore[fKey] as Array; } catch (e:Error) {}
			}
			_filterStore = new Dictionary(true);

			for (var hKey:* in _hidden)
			{
				try { DisplayObject(hKey).visible = true; } catch (e:Error) {}
			}
			_hidden = new Dictionary(true);
		}
	}
}
