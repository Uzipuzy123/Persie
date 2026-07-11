package skua.module
{
	import flash.display.Bitmap;
	import flash.display.MovieClip;
	import flash.display.Sprite;

	// Dedicated skin module for yulgar's "Enter" room (the main bar area) —
	// split out from MapSkin so this one map can run much higher-resolution
	// art (2880x1650, 3x the game's 960x550 stage, at max JPEG quality)
	// independently, as its own toggle, without bloating every other room's
	// asset size to match. Same mechanism as MapSkin otherwise: hides the
	// real world.map (functional pieces — NPCs, doors — live as siblings of
	// map, not children, so they're untouched) and layers this picture in
	// its old spot.
	public class YulgarSkin extends Module implements ISkinModule
	{
		[Embed(source="../assets/yulgar_bar_hq.jpg")]
		private static const BgArt:Class;

		private static const TARGET_MAP:String   = "yulgar";
		private static const TARGET_LABEL:String = "Enter";

		// Display box stays in the game's real 960x550 stage units — only the
		// SOURCE art resolution changed. Calibrated via Map Debug.
		private static const STAGE_W:Number = 960;
		private static const STAGE_H:Number = 550;
		private static const OFFSET_X:Number = -63.95;
		private static const OFFSET_Y:Number = -26.55;

		private var _container:Sprite     = null;
		private var _appliedMap:MovieClip = null;

		public function YulgarSkin() { super("YulgarSkin"); }

		override public function onToggle(game:*):void
		{
			if (!enabled) restore(game);
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			try
			{
				var world:* = game.world;
				var map:MovieClip = world.map as MovieClip;

				if (map == null || world.strMapName != TARGET_MAP)
				{
					if (_appliedMap != null) restore(game);
					return;
				}

				var label:String = null;
				try { label = map.currentLabel; } catch (e:Error) {}

				if (label != TARGET_LABEL)
				{
					if (_appliedMap != null) restore(game);
					return;
				}
				if (map === _appliedMap) return;

				apply(game, world, map);
			}
			catch (e:Error) {}
		}

		private function apply(game:*, world:*, map:MovieClip):void
		{
			try
			{
				map.alpha = 0;

				if (_container == null)
				{
					_container = new Sprite();
					var bitmap:Bitmap = new BgArt() as Bitmap;
					bitmap.smoothing = true;
					bitmap.width  = STAGE_W;
					bitmap.height = STAGE_H;
					_container.addChild(bitmap);
					_container.mouseEnabled  = false;
					_container.mouseChildren = false;
					_container.x = OFFSET_X;
					_container.y = OFFSET_Y;
				}
				if (_container.parent) _container.parent.removeChild(_container);

				var idx:int = world.getChildIndex(map);
				world.addChildAt(_container, idx + 1);

				_appliedMap = map;
			}
			catch (e:Error) {}
		}

		private function restore(game:*):void
		{
			try
			{
				if (_container != null && _container.parent) _container.parent.removeChild(_container);
				var world:* = game.world;
				if (world != null && world.map != null) world.map.alpha = 1;
			}
			catch (e:Error) {}
			_appliedMap = null;
		}

		// ── accessor for MapDebug ───────────────────────────────────────────

		public function getContainer():Sprite { return _container; }
	}
}
