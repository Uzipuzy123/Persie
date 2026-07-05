package skua.module
{
	import flash.display.Sprite;
	import flash.filters.BevelFilter;
	import flash.filters.DropShadowFilter;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	public class RevengeKill extends Module
	{
		private var _lastHP:Object     = {};
		private var _dead:Object       = {};
		private var _ownLastHP:Number  = -1;
		private var _lastKiller:String = null;

		private var _overlay:Sprite = null;
		private var _ttl:int        = 0;

		private static const ANNOUNCE_TTL:int = 90;
		private static const FADE_IN:int      = 14;
		private static const FADE_OUT:int     = 22;

		public function RevengeKill() { super("RevengeKill"); }

		override public function onToggle(game:*):void
		{
			if (!enabled)
			{
				removeOverlay();
				_lastHP     = {};
				_dead       = {};
				_ownLastHP  = -1;
				_lastKiller = null;
			}
		}

		override public function onFrame(game:*):void
		{
			trackEvents(game);
			updateOverlay();
		}

		private function trackEvents(game:*):void
		{
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			try
			{
				var myHP:Number = Number(game.world.myAvatar.dataLeaf.intHP);
				if (_ownLastHP > 0 && myHP <= 0)
				{
					try
					{
						var t:* = game.world.myAvatar.target;
						if (t && t.objData)
							_lastKiller = String(t.objData.strUsername).toLowerCase();
					}
					catch (ek:Error) {}
				}
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

					if (hp > 0 && _dead[aid]) delete _dead[aid];
					else if (hp <= 0 && prev > 0 && !_dead[aid])
					{
						_dead[aid] = true;
						if (_lastKiller != null)
						{
							var killed:String = "";
							try { killed = String(av.objData.strUsername).toLowerCase(); } catch (ek:Error) {}
							if (killed != "" && killed == _lastKiller)
							{
								_lastKiller = null;
								showBanner(game);
							}
						}
					}
					_lastHP[aid] = hp;
				}
				catch (e:Error) {}
			}
		}

		private function showBanner(game:*):void
		{
			removeOverlay();

			_overlay = new Sprite();
			_overlay.mouseEnabled  = false;
			_overlay.mouseChildren = false;

			var tf:TextField = new TextField();
			tf.selectable   = false;
			tf.mouseEnabled = false;
			tf.autoSize     = TextFieldAutoSize.CENTER;
			tf.defaultTextFormat = new TextFormat("Arial Black", 38, 0xCC6600, true,
			                                       null, null, null, null, "center");
			tf.text = "REVENGE!";
			tf.x = -tf.textWidth  / 2;
			tf.y = -tf.textHeight / 2 - 1;
			_overlay.addChild(tf);

			_overlay.filters = [
				new BevelFilter(2, 135, 0xFFCC00, 0.80, 0x331100, 0.95, 3, 3, 2, 1, "inner"),
				new DropShadowFilter(4, 135, 0x000000, 0.80, 5, 5, 1, 1)
			];

			var sw:Number = 800, sh:Number = 600;
			try { sw = game.stage.stageWidth; sh = game.stage.stageHeight; } catch (e:Error) {}
			_overlay.x = sw / 2;
			_overlay.y = sh * 0.36;

			try { game.stage.addChild(_overlay); }
			catch (e:Error) { try { game.parent.addChild(_overlay); } catch (e2:Error) {} }

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
