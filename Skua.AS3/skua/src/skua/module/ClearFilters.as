package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.utils.Dictionary;

	public class ClearFilters extends Module
	{
		private static const EMPTY:Array = [];

		// Weak-key: { f: Array (filters), b: String (blendMode) } per object.
		private var _store:Dictionary;
		// Avatar pMCs managed by HighlightEnemies — rebuilt each frame, never swept.
		private var _avatarPMCs:Dictionary = new Dictionary(true);

		public function ClearFilters()
		{
			super("ClearFilters");
		}

		override public function onToggle(game:*):void
		{
			if (enabled)
			{
				_store = new Dictionary(true);
				apply(game);
			}
			else
			{
				restore();
				_store = null;
			}
		}

		override public function onFrame(game:*):void
		{
			apply(game);
		}

		private function apply(game:*):void
		{
			// Rebuild skip set — avatar pMCs are owned by HighlightEnemies
			_avatarPMCs = new Dictionary(true);
			try
			{
				for (var aid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[aid];
					if (av && av.pMC) _avatarPMCs[av.pMC] = true;
				}
			}
			catch (e:Error) {}
			try { sweep(game); } catch (e:Error) {}
		}

		private function restore():void
		{
			if (_store == null) return;
			for (var key:* in _store)
			{
				try
				{
					var obj:DisplayObject = DisplayObject(key);
					var saved:Object = _store[key];
					obj.filters      = saved.f as Array;
					obj.blendMode    = saved.b as String;
					obj.cacheAsBitmap = (saved.f as Array).length > 0;
				}
				catch (e:Error) {}
			}
		}

		private function sweep(obj:DisplayObject):void
		{
			try
			{
				if (_avatarPMCs[obj]) return;
				var hasFilters:Boolean = obj.filters.length > 0;
				var hasBlend:Boolean   = obj.blendMode != "normal";

				if (hasFilters || hasBlend)
				{
					if (_store != null && _store[obj] === undefined)
						_store[obj] = { f: obj.filters, b: obj.blendMode };

					if (hasFilters)
					{
						obj.filters = EMPTY;
						obj.cacheAsBitmap = false;
					}
					if (hasBlend)
						obj.blendMode = "normal";
				}

				if (obj is DisplayObjectContainer)
				{
					var doc:DisplayObjectContainer = DisplayObjectContainer(obj);
					for (var i:int = 0; i < doc.numChildren; i++)
						sweep(doc.getChildAt(i));
				}
			}
			catch (e:Error) {}
		}
	}
}
