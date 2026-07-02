package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;

	public class OptimizeMap extends Module
	{
		private var _mapRef:Object;

		public function OptimizeMap() { super("OptimizeMap"); }

		override public function onToggle(game:*):void
		{
			if (!enabled)
			{
				restore(game);
				_mapRef = null;
			}
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			try
			{
				var map:Object = game.world.map;
				if (!map || map === _mapRef) return;
				_mapRef = map;
				apply(map);
			}
			catch (e:Error) {}
		}

		private function apply(map:Object):void
		{
			try
			{
				// Only target known art-only layers — never the map container itself
				// so clicks on enemies, NPCs, and interactive objects still register
				setMouse(map.ground,       false);
				setMouse(map.background,   false);
				setMouse(map.bg,           false);
				setMouse(map.sky,          false);

				setCache(map.ground,       true);
				setCache(map.background,   true);
				setCache(map.bg,           true);
				setCache(map.sky,          true);
			}
			catch (e:Error) {}
		}

		private function restore(game:*):void
		{
			try
			{
				var map:Object = game.world.map;
				if (!map) return;

				setMouse(map.ground,       true);
				setMouse(map.background,   true);
				setMouse(map.bg,           true);
				setMouse(map.sky,          true);

				setCache(map.ground,       false);
				setCache(map.background,   false);
				setCache(map.bg,           false);
				setCache(map.sky,          false);
			}
			catch (e:Error) {}
		}

		private function setMouse(obj:*, on:Boolean):void
		{
			try
			{
				if (!obj) return;
				var doc:DisplayObjectContainer = obj as DisplayObjectContainer;
				if (doc)
				{
					doc.mouseChildren = on;
					doc.mouseEnabled  = on;
				}
			}
			catch (e:Error) {}
		}

		private function setCache(obj:*, on:Boolean):void
		{
			try { if (obj) DisplayObject(obj).cacheAsBitmap = on; }
			catch (e:Error) {}
		}
	}
}
