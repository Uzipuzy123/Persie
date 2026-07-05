package skua.module
{
	import flash.display.Sprite;
	import flash.geom.ColorTransform;

	public class KillFlash extends Module
	{
		private var _lastHP:Object = {};
		private var _dead:Object   = {};

		private var _screenFlash:Sprite = null;
		private var _screenTTL:int      = 0;
		private var _screenAlpha:Number = 0.38;
		private var _isDouble:Boolean   = false;

		private var _playerFlashes:Object = {};

		private var _screenStyle:int = 0;
		private var _playerStyle:int = 0;

		private static const BASE_TTL:int = 12;

		// [colorHex, alpha, isDouble]  — must match XAML KillFlash tab row order
		private static const SCREEN_STYLES:Array = [
			[0xFFFFFF, 0.65, false], // 1: White Flash
			[0xFF0000, 0.50, false], // 2: Red Rush
			[0xFFAA00, 0.55, false], // 3: Gold Strike
			[0x0022FF, 0.45, false], // 4: Blue Freeze
			[0xAA00FF, 0.55, false], // 5: Purple Hex
			[0x00FF44, 0.45, false], // 6: Green Vengeance
			[0xFF00CC, 0.60, false], // 7: Pink Burst
			[0x00EECC, 0.50, false], // 8: Teal Wave
			[0xFFFFFF, 0.70,  true], // 9: Double White
			[0xFF0000, 0.60,  true], // 10: Double Red
			[0xFF6600, 0.65, false], // 11: Orange Fury
		];

		// [rOff, gOff, bOff, isVoid, ttl]
		private static const PLAYER_STYLES:Array = [
			[255, 255, 255, false, 25], // 1: Bleach White
			[255,   0,   0, false, 25], // 2: Blood Splatter
			[255, 180,   0, false, 25], // 3: Gold Victory
			[  0,  80, 255, false, 25], // 4: Ice Blue
			[255, 255, 255, false, 55], // 5: Ghost (slow)
			[180,   0, 255, false, 25], // 6: Purple Curse
			[255, 100,   0, false, 25], // 7: Orange Burn
			[  0,   0,   0, true,  30], // 8: Void Black
			[255,   0, 180, false, 25], // 9: Electric Pink
		];

		public function KillFlash() { super("KillFlash"); }

		public function setScreenStyle(n:int):void { _screenStyle = n; if (n == 0) removeScreenFlash(); }
		public function setPlayerStyle(n:int):void { _playerStyle = n; if (n == 0) clearPlayerFlashes(); }

		override public function onToggle(game:*):void
		{
			if (!enabled)
			{
				removeScreenFlash();
				clearPlayerFlashes();
				_lastHP = {};
				_dead   = {};
			}
		}

		override public function onFrame(game:*):void
		{
			scanKills(game);
			tickScreenFlash();
			tickPlayerFlashes();
		}

		private function scanKills(game:*):void
		{
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			for (var aid:* in game.world.avatars)
			{
				var av:* = game.world.avatars[aid];
				try
				{
					if (!av || av.isMyAvatar || !av.dataLeaf) continue;

					var isEnemy:Boolean = true;
					try
					{
						if (myTeam != null && av.objData.strTeam != null)
							isEnemy = (myTeam != av.objData.strTeam);
					}
					catch (e2:Error) {}
					if (!isEnemy) continue;

					var hp:Number   = Number(av.dataLeaf.intHP);
					var prev:Number = (_lastHP[aid] !== undefined) ? Number(_lastHP[aid]) : hp;

					if (hp > 0 && _dead[aid])
						delete _dead[aid];
					else if (hp <= 0 && prev > 0 && !_dead[aid])
					{
						_dead[aid] = true;
						if (_screenStyle > 0 && _screenStyle <= SCREEN_STYLES.length)
							showScreenFlash(game);
						if (_playerStyle > 0 && _playerStyle <= PLAYER_STYLES.length && av.pMC)
							recordPlayerFlash(String(aid), av.pMC);
					}
					_lastHP[aid] = hp;
				}
				catch (e:Error) {}
			}
		}

		private function showScreenFlash(game:*):void
		{
			removeScreenFlash();
			var sd:Array  = SCREEN_STYLES[_screenStyle - 1];
			var sw:Number = 800, sh:Number = 600;
			try { sw = game.stage.stageWidth; sh = game.stage.stageHeight; } catch (e:Error) {}

			_screenFlash = new Sprite();
			_screenFlash.mouseEnabled = false;
			_screenFlash.graphics.beginFill(uint(sd[0]), 1.0);
			_screenFlash.graphics.drawRect(0, 0, sw, sh);
			_screenFlash.graphics.endFill();
			_screenAlpha      = Number(sd[1]);
			_isDouble         = Boolean(sd[2]);
			_screenFlash.alpha = _screenAlpha;

			try { game.stage.addChild(_screenFlash); }
			catch (e:Error) { try { game.parent.addChild(_screenFlash); } catch (e2:Error) {} }

			_screenTTL = _isDouble ? BASE_TTL * 2 : BASE_TTL;
		}

		private function tickScreenFlash():void
		{
			if (_screenFlash == null) return;
			_screenTTL--;
			if (_screenTTL <= 0) { removeScreenFlash(); return; }
			if (_isDouble)
				_screenFlash.alpha = _screenAlpha * Math.abs(Math.sin(Math.PI * _screenTTL / BASE_TTL));
			else
				_screenFlash.alpha = _screenAlpha * (_screenTTL / BASE_TTL);
		}

		private function removeScreenFlash():void
		{
			if (_screenFlash != null)
			{
				try { _screenFlash.parent.removeChild(_screenFlash); } catch (e:Error) {}
				_screenFlash = null;
			}
			_screenTTL = 0;
		}

		private function recordPlayerFlash(aid:String, pmc:*):void
		{
			var sd:Array = PLAYER_STYLES[_playerStyle - 1];
			_playerFlashes[aid] = {
				pmc:    pmc,
				ttl:    int(sd[4]),
				maxTtl: int(sd[4]),
				ro:     int(sd[0]),
				go:     int(sd[1]),
				bo:     int(sd[2]),
				isVoid: Boolean(sd[3])
			};
		}

		private function tickPlayerFlashes():void
		{
			for (var k:* in _playerFlashes)
			{
				var f:* = _playerFlashes[k];
				f.ttl--;
				var t:Number = Number(f.ttl) / Number(f.maxTtl);
				try
				{
					if (f.ttl <= 0)
					{
						f.pmc.transform.colorTransform = new ColorTransform();
						delete _playerFlashes[k];
					}
					else if (f.isVoid)
						f.pmc.transform.colorTransform = new ColorTransform(0.15 + t * 0.85, 0.15 + t * 0.85, 0.15 + t * 0.85, 1);
					else
						f.pmc.transform.colorTransform = new ColorTransform(1, 1, 1, 1, f.ro * t, f.go * t, f.bo * t, 0);
				}
				catch (e:Error) { delete _playerFlashes[k]; }
			}
		}

		private function clearPlayerFlashes():void
		{
			for (var k:* in _playerFlashes)
			{
				var f:* = _playerFlashes[k];
				try { f.pmc.transform.colorTransform = new ColorTransform(); } catch (e:Error) {}
			}
			_playerFlashes = {};
		}
	}
}
