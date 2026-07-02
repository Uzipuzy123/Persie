package skua.module
{
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.filters.GlowFilter;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	public class KillStreakAnnouncer extends Module
	{
		private var _lastHP:Object    = {};
		private var _dead:Object      = {};
		private var _streak:int       = 0;
		private var _streakTimer:int  = 0;
		private var _ownLastHP:Number = -1;

		private var _overlay:Sprite = null;
		private var _ttl:int        = 0;

		private static const STREAK_TIMEOUT:int = 600;
		private static const ANNOUNCE_TTL:int   = 95;
		private static const FADE_IN:int        = 14;
		private static const FADE_OUT:int       = 22;

		public function KillStreakAnnouncer() { super("KillStreakAnnouncer"); }

		override public function onToggle(game:*):void
		{
			if (!enabled)
			{
				removeOverlay();
				_streak      = 0;
				_streakTimer = 0;
				_lastHP      = {};
				_dead        = {};
				_ownLastHP   = -1;
			}
		}

		override public function onFrame(game:*):void
		{
			if (_streakTimer > 0 && --_streakTimer == 0) _streak = 0;
			trackDeaths(game);
			updateOverlay();
		}

		private function trackDeaths(game:*):void
		{
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			try
			{
				var myHP:Number = Number(game.world.myAvatar.dataLeaf.intHP);
				if (_ownLastHP > 0 && myHP <= 0) { _streak = 0; _streakTimer = 0; }
				_ownLastHP = myHP;
			}
			catch (e:Error) {}

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
					{
						delete _dead[aid];
					}
					else if (hp <= 0 && prev > 0 && !_dead[aid])
					{
						_dead[aid]   = true;
						_streak++;
						_streakTimer = STREAK_TIMEOUT;
						showAnnouncement(game);
					}

					_lastHP[aid] = hp;
				}
				catch (e:Error) {}
			}
		}

		private function showAnnouncement(game:*):void
		{
			var msg:String;
			var col:uint;
			var glowCol:uint;

			switch (_streak)
			{
				case 1:  msg = "FIRST BLOOD";  col = 0xFF4444; glowCol = 0xFF0000; break;
				case 2:  msg = "DOUBLE KILL";  col = 0xFFFFFF; glowCol = 0x6699FF; break;
				case 3:  msg = "TRIPLE KILL";  col = 0xFFEE00; glowCol = 0xFFAA00; break;
				case 4:  msg = "QUADRA KILL";  col = 0xFF8800; glowCol = 0xFF4400; break;
				case 5:  msg = "PENTA KILL";   col = 0xFF2200; glowCol = 0xFF0000; break;
				default: msg = "LEGENDARY!";   col = 0xFF44FF; glowCol = 0xCC00CC; break;
			}

			removeOverlay();

			_overlay = new Sprite();
			_overlay.mouseEnabled  = false;
			_overlay.mouseChildren = false;

			var g:* = _overlay.graphics;
			g.beginFill(0x000000, 0.62);
			g.drawRoundRect(-228, -32, 456, 64, 14);
			g.endFill();

			var tf:TextField = new TextField();
			tf.selectable   = false;
			tf.mouseEnabled = false;
			tf.autoSize     = TextFieldAutoSize.CENTER;
			tf.defaultTextFormat = new TextFormat("Arial", 38, col, true,
			                                       null, null, null, null, "center");
			tf.text = msg;
			tf.x = -tf.textWidth  / 2;
			tf.y = -tf.textHeight / 2 - 1;
			_overlay.addChild(tf);

			_overlay.filters = [new GlowFilter(glowCol, 0.90, 12, 12, 3, 1)];

			var sw:Number = 800, sh:Number = 600;
			try { sw = game.stage.stageWidth; sh = game.stage.stageHeight; } catch (e:Error) {}
			_overlay.x = sw / 2;
			_overlay.y = sh * 0.26;

			try
			{
				var st:Stage = game.stage as Stage;
				st.addChild(_overlay);
			}
			catch (e:Error)
			{
				try { game.parent.addChild(_overlay); } catch (e2:Error) {}
			}

			_ttl = ANNOUNCE_TTL;
		}

		private function updateOverlay():void
		{
			if (_overlay == null || _ttl <= 0) return;
			_ttl--;
			if (_ttl <= 0) { removeOverlay(); return; }

			var elapsed:int = ANNOUNCE_TTL - _ttl;

			if (elapsed < FADE_IN)
			{
				var t:Number = elapsed / FADE_IN;
				_overlay.alpha  = t;
				_overlay.scaleX = _overlay.scaleY = 0.55 + 0.45 * t;
			}
			else if (_ttl < FADE_OUT)
			{
				_overlay.alpha  = _ttl / FADE_OUT;
				_overlay.scaleX = _overlay.scaleY = 1.0;
			}
			else
			{
				_overlay.alpha  = 1.0;
				_overlay.scaleX = _overlay.scaleY = 1.0;
			}
		}

		private function removeOverlay():void
		{
			if (_overlay != null)
			{
				try { _overlay.parent.removeChild(_overlay); } catch (e:Error) {}
				_overlay = null;
			}
			_ttl = 0;
		}
	}
}
