package skua.module
{
	import flash.display.Bitmap;
	import flash.display.MovieClip;
	import flash.display.Sprite;

	// Replaces real map art with static pictures, one per game-phase room,
	// across multiple maps — while leaving every functional piece (portals,
	// monsters, NPCs, room-hop markers) untouched — those live as siblings of
	// world.map, not children of it, so hiding map and layering our own art
	// in its old spot doesn't affect them. Only touches world.map's alpha —
	// deliberately does NOT also force stage.quality = "LOW" the way "Go
	// Beyond" (Skua.App.WPF/QualityWindow.xaml.cs) does: that's a genuine
	// performance trick for rendering the complex vector map faster, but it
	// also disables anti-aliasing/bitmap smoothing for everything, which just
	// makes our flat picture (and everything else) look worse for no benefit
	// once the real map is hidden anyway.
	//
	// world.map is one long timeline that jumps between named labels as the
	// current room/phase changes (confirmed live via Map Debug's label
	// readout — e.g. bludrutbrawl: Wait/Captain0/Morale0A/Enter0/etc; yulgar:
	// Wait/Enter/Fireplace/Upstairs/Bathroom/Attic/Room/Blank) — each label
	// shows a different physical room, so each needs its own picture, its own
	// calibrated offset, and is scoped to its own map (strMapName) in case
	// two different maps ever reuse the same label name.
	//
	// Positioning is calibrated separately via the "Map Debug" module/toggle
	// (MapDebug.as) — drag/nudge it there, then hardcode the final numbers
	// into the matching SKINS entry below. This module stays a plain on/off
	// with no debug tooling of its own so normal use stays simple.
	// yulgar's "Enter" room lives in its own dedicated module (YulgarSkin.as)
	// instead of this table — it gets its own toggle so its much
	// higher-resolution/quality art can be pushed independently of these.
	public class MapSkin extends Module implements ISkinModule
	{
		[Embed(source="../assets/bludrutbrawl.jpg")]
		private static const BgArt_Morale0C:Class;

		[Embed(source="../assets/bludrutbrawl1.jpg")]
		private static const BgArt_Enter0:Class;

		[Embed(source="../assets/captain0.jpg")]
		private static const BgArt_Captain0:Class;

		[Embed(source="../assets/morale0b.jpg")]
		private static const BgArt_Morale0B:Class;

		// One entry per calibrated room. "map" must match world.strMapName
		// exactly, "label" must match world.map's currentLabel exactly. w/h
		// are that map's own native stage size (each map can differ — e.g.
		// bludrutbrawl is 960x550). x/y come from Map Debug (drag/nudge,
		// then copy-to-clipboard) — 0/0 is just a starting point until the
		// real position is measured live.
		private static const SKINS:Array = [
			{ map: "bludrutbrawl", label: "Morale0C", art: BgArt_Morale0C,  w: 960, h: 550, x: 20.95, y: -57.85 },
			{ map: "bludrutbrawl", label: "Enter0",   art: BgArt_Enter0,    w: 960, h: 550, x: 0, y: -53.45 },
			// Captain0's real room content is NOT 960-wide at the stage's own
			// origin — measured directly via Map Debug's B key (Flash's own
			// DisplayObject.getBounds(), not a screenshot guess): the real
			// map deliberately overhangs both stage edges, positioned at
			// (-243.35,-59.30) sized 1447.70x569.65 (aspect 2.541). Matching
			// those exact numbers here is what makes the picture reach the
			// true edges instead of leaving gaps.
			{ map: "bludrutbrawl", label: "Captain0", art: BgArt_Captain0,  w: 1447.70, h: 569.65, x: -236.75, y: -64.80 },
			// Confirmed live via Map Debug — the room next to Morale0C is
			// indeed Morale0B.
			{ map: "bludrutbrawl", label: "Morale0B", art: BgArt_Morale0B,  w: 960, h: 550, x: -1.65, y: -56.1 },
		];

		private var _containers:Object      = {}; // "map:label" -> Sprite, built lazily & reused
		private var _activeContainer:Sprite = null;
		private var _appliedKey:String      = null;
		private var _appliedMap:MovieClip   = null;

		public function MapSkin() { super("MapSkin"); }

		override public function onToggle(game:*):void
		{
			if (!enabled) restore(game);
			// onFrame() picks up the apply side — the right map/label might
			// not be active yet at the moment this toggles on.
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			try
			{
				var world:* = game.world;
				var map:MovieClip = world.map as MovieClip;
				var mapName:String = world.strMapName;

				if (map == null || mapName == null)
				{
					if (_appliedKey != null) restore(game);
					return;
				}

				var label:String = null;
				try { label = map.currentLabel; } catch (e:Error) {}

				var skin:Object = findSkin(mapName, label);
				if (skin == null)
				{
					// Same map instance keeps playing through every phase —
					// only the LABEL changes — so a phase with no matching
					// picture must restore even though "map" itself hasn't
					// changed instance.
					if (_appliedKey != null) restore(game);
					return;
				}

				var key:String = mapName + ":" + label;
				if (key == _appliedKey && map === _appliedMap) return;

				apply(game, world, map, skin, key);
			}
			catch (e:Error) {}
		}

		private function findSkin(mapName:String, label:String):Object
		{
			if (mapName == null || label == null) return null;
			for each (var s:Object in SKINS)
			{
				if (s.map == mapName && s.label == label) return s;
			}
			return null;
		}

		private function apply(game:*, world:*, map:MovieClip, skin:Object, key:String):void
		{
			try
			{
				map.alpha = 0;

				var container:Sprite = _containers[key] as Sprite;
				if (container == null)
				{
					container = new Sprite();
					var bmpClass:Class = skin.art as Class;
					var bitmap:Bitmap = new bmpClass() as Bitmap;
					bitmap.smoothing = true; // AS3 defaults this to false — without it, any non-1:1 scaling looks blocky/aliased
					// Embedded source art is 2x this map's native stage size —
					// embed.html stretches the whole game stage to fill the
					// browser window (scale="exactFit"), which can be much
					// bigger than the map's native pixels, and a bitmap has no
					// extra detail to give when stretched past its own native
					// size. The 2x source leaves headroom before that shows.
					bitmap.width  = skin.w;
					bitmap.height = skin.h;
					container.addChild(bitmap);
					container.mouseEnabled  = false;
					container.mouseChildren = false;
					container.x = skin.x;
					container.y = skin.y;
					_containers[key] = container;
				}

				if (_activeContainer != null && _activeContainer !== container && _activeContainer.parent)
				{
					_activeContainer.parent.removeChild(_activeContainer);
				}
				if (container.parent) container.parent.removeChild(container);

				var idx:int = world.getChildIndex(map);
				world.addChildAt(container, idx + 1);

				_activeContainer = container;
				_appliedKey = key;
				_appliedMap = map;
			}
			catch (e:Error) {}
		}

		private function restore(game:*):void
		{
			try
			{
				if (_activeContainer != null && _activeContainer.parent) _activeContainer.parent.removeChild(_activeContainer);
				var world:* = game.world;
				if (world != null && world.map != null) world.map.alpha = 1;
			}
			catch (e:Error) {}
			_activeContainer = null;
			_appliedKey = null;
			_appliedMap = null;
		}

		// ── accessor for MapDebug — whichever room's picture is currently up ─

		public function getContainer():Sprite { return _activeContainer; }
	}
}
