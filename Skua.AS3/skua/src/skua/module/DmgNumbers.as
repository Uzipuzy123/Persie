package skua.module
{
	import flash.display.Sprite;
	import flash.filters.GlowFilter;
	import flash.geom.ColorTransform;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	public class DmgNumbers extends Module
	{
		private var _styleId:int       = 0;
		private var _lastHP:Object     = {};
		private var _avgDmg:Object     = {};
		private var _nums:Array        = [];
		private var _pMCbl:Object      = {};
		private var _worldKnown:Object = null;
		private var _ours:Object       = {};

		private static const ZERO_ALPHA:ColorTransform = new ColorTransform(1, 1, 1, 0);
		private static const FADE_FRAMES:int = 22;

		public function DmgNumbers()
		{
			super("DmgNumbers");
		}

		public function setStyle(id:int):void { _styleId = id; }

		override public function onToggle(game:*):void
		{
			if (!enabled)
			{
				clearAll();
				_lastHP     = {};
				_avgDmg     = {};
				_pMCbl      = {};
				_worldKnown = null;
				_ours       = {};
			}
		}

		override public function onFrame(game:*):void
		{
			updateFloating();
			suppressDefault(game);
			trackDamage(game);
		}

		private function suppressDefault(game:*):void
		{
			suppressOnDict(game.world.avatars, "a_");
			try { suppressOnDict(game.world.monsters, "m_"); } catch (e:Error) {}
			suppressWorldLayer(game);
		}

		private function suppressOnDict(dict:*, prefix:String):void
		{
			for (var key:* in dict)
			{
				var entity:* = dict[key];
				try
				{
					if (!entity || !entity.pMC) continue;
					var pMC:*       = entity.pMC;
					var bKey:String = prefix + String(key);
					var bl:Object   = _pMCbl[bKey];

					if (!bl)
					{
						bl = {};
						for (var j:int = 0; j < pMC.numChildren; j++)
							bl[pMC.getChildAt(j)] = true;
						_pMCbl[bKey] = bl;
						continue;
					}

					for (var k:int = 0; k < pMC.numChildren; k++)
					{
						var child:* = pMC.getChildAt(k);
						if (bl[child] || _ours[child]) continue;

						var cname:String = String(child.name);
						if (cname.indexOf("skua_") == 0)
						{
							bl[child] = true;
							continue;
						}

						child.transform.colorTransform = ZERO_ALPHA;
					}
				}
				catch (e:Error) {}
			}
		}

		private function suppressWorldLayer(game:*):void
		{
			try
			{
				var layer:* = game.world.myAvatar.pMC.parent;
				if (!layer) return;

				if (!_worldKnown)
				{
					_worldKnown = {};
					for (var j:int = 0; j < layer.numChildren; j++)
						_worldKnown[layer.getChildAt(j)] = true;
					return;
				}

				for (var aid:* in game.world.avatars)
					try { if (game.world.avatars[aid].pMC) _worldKnown[game.world.avatars[aid].pMC] = true; } catch (e2:Error) {}
				try
				{
					for (var mid:* in game.world.monsters)
						try { if (game.world.monsters[mid].pMC) _worldKnown[game.world.monsters[mid].pMC] = true; } catch (e3:Error) {}
				}
				catch (e:Error) {}

				for (var k:int = 0; k < layer.numChildren; k++)
				{
					var child:* = layer.getChildAt(k);
					if (!_worldKnown[child] && !_ours[child])
						child.transform.colorTransform = ZERO_ALPHA;
				}
			}
			catch (e:Error) {}
		}

		private function trackDamage(game:*):void
		{
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			for (var aid:* in game.world.avatars)
			{
				var av:* = game.world.avatars[aid];
				try
				{
					if (!av || !av.pMC || !av.dataLeaf) continue;
					var hp:int    = int(av.dataLeaf.intHP);
					var maxHP:int = int(av.dataLeaf.intHPMax);
					if (maxHP <= 0) maxHP = 1;
					var aKey:String = "a_" + String(aid);

					if (_lastHP[aKey] !== undefined)
					{
						var delta:int = hp - int(_lastHP[aKey]);
						if (delta > maxHP * 0.5) { _lastHP[aKey] = hp; continue; }
						if (delta != 0)
						{
							var isHealA:Boolean  = delta > 0;
							var isEnemyA:Boolean = resolveEnemy(av, myTeam);
							var absA:int         = Math.abs(delta);
							var isCritA:Boolean  = detectCrit(aKey, absA, isHealA);
							spawn(av.pMC, absA, isHealA, isEnemyA, isCritA);
						}
					}
					_lastHP[aKey] = hp;
				}
				catch (e:Error) {}
			}

			try
			{
				for (var mid:* in game.world.monsters)
				{
					var mon:* = game.world.monsters[mid];
					try
					{
						if (!mon || !mon.pMC) continue;
						var mhp:int, mmhp:int;
						try    { mhp = int(mon.intHP);    mmhp = int(mon.intHPMax); }
						catch  (e:Error) { mhp = int(mon.objData.intHP); mmhp = int(mon.objData.intHPMax); }
						if (mmhp <= 0) mmhp = 1;
						var mKey:String = "m_" + String(mid);

						if (_lastHP[mKey] !== undefined)
						{
							var mdelta:int = mhp - int(_lastHP[mKey]);
							if (mdelta > mmhp * 0.5) { _lastHP[mKey] = mhp; continue; }
							if (mdelta < 0)
							{
								var absM:int        = -mdelta;
								var isCritM:Boolean = detectCrit(mKey, absM, false);
								spawn(mon.pMC, absM, false, true, isCritM);
							}
						}
						_lastHP[mKey] = mhp;
					}
					catch (e:Error) {}
				}
			}
			catch (e:Error) {}
		}

		private function detectCrit(key:String, value:int, isHeal:Boolean):Boolean
		{
			if (isHeal || value <= 0) return false;
			var prev:Number = (_avgDmg[key] > 0) ? Number(_avgDmg[key]) : value;
			_avgDmg[key] = prev * 0.80 + value * 0.20;
			return value >= prev * 1.5;
		}

		private function resolveEnemy(av:*, myTeam:*):Boolean
		{
			if (av.isMyAvatar) return false;
			try
			{
				if (myTeam != null && av.objData.strTeam != null)
					return myTeam != av.objData.strTeam;
			}
			catch (e:Error) {}
			return true;
		}

		private function spawn(pMC:*, value:int, isHeal:Boolean,
		                       isEnemy:Boolean, isCrit:Boolean):void
		{
			try
			{
				var spawnY:Number;
				try   { spawnY = pMC.pname.y - 55; }
				catch (e:Error) { spawnY = -100; }

				var sp:Sprite = new Sprite();
				sp.mouseEnabled  = false;
				sp.mouseChildren = false;
				sp.x = (Math.random() - 0.5) * (isCrit ? 30 : 24);
				sp.y = spawnY;

				var vy:Number, vx:Number, ttl:int;
				var useGravity:Boolean = false;

				switch (_styleId)
				{
					case 0:
					{
						var text0:String = isCrit ? (String(value) + "!") : String(value);
						var fs0:int  = isCrit ? 30 : (value > 300 ? 24 : (value > 100 ? 22 : 20));
						var col0:uint;
						if (isHeal)                  col0 = 0x44FF88;
						else if (isCrit && !isEnemy) col0 = 0xFF0000;
						else if (!isEnemy)           col0 = 0xFF3333;
						else if (isCrit)             col0 = 0xFFFFAA;
						else                         col0 = 0xFFEE00;

						var sOff0:int = isCrit ? 2 : 1;
						var shd0:TextField = makeTF(text0, fs0, 0x000000, true);
						shd0.x = sOff0; shd0.y = sOff0;
						sp.addChild(shd0);
						sp.addChild(makeTF(text0, fs0, col0, true));
						vy = isCrit ? -3.2 : -2.2; vx = 0; ttl = 100;
						break;
					}

					case 1:
					{
						var fs1:int = isCrit ? 34 : (value > 500 ? 30 : (value > 200 ? 26 : (value > 80 ? 23 : 20)));
						var col1:uint;
						if (isHeal)           col1 = 0x00FF88;
						else if (isCrit)      col1 = 0xFF0055;
						else if (value > 500) col1 = 0xFF2200;
						else if (value > 200) col1 = 0xFF8800;
						else if (value > 80)  col1 = 0xFFFF00;
						else                  col1 = 0x00FFFF;

						sp.addChild(makeTF(String(value), fs1, col1, true));
						sp.filters = [new GlowFilter(col1, 0.9, isCrit ? 10 : 5, isCrit ? 10 : 5, isCrit ? 4 : 2, 1)];
						vy = isCrit ? -6.0 : -4.5;
						vx = (Math.random() - 0.5) * (isCrit ? 2.5 : 1.6);
						ttl = 90; useGravity = true;
						break;
					}

					case 2:
					{
						var text2:String = (isHeal ? "+" : "") + String(value);
						var fs2:int   = isCrit ? 26 : 20;
						var col2:uint = isHeal ? 0x44FF88 : (isCrit ? 0xFF2222 : 0xFF4444);
						sp.addChild(makeTF(text2, fs2, col2, isCrit));
						vy = isCrit ? -2.8 : -1.8; vx = 0; ttl = 90;
						break;
					}

					case 3:
					{
						var text3:String = isCrit ? (String(value) + "!") : String(value);
						var fs3:int  = isCrit ? 30 : (value > 250 ? 26 : 22);
						var col3:uint;
						if (isHeal)           col3 = 0x1EFF00;
						else if (isCrit)      col3 = 0xFFD700;
						else if (value > 250) col3 = 0xFFB347;
						else                  col3 = 0xE8E8D0;

						var sOff3:int = isCrit ? 2 : 1;
						var shd3:TextField = makeTF(text3, fs3, 0x1A1A0A, true);
						shd3.x = sOff3; shd3.y = sOff3;
						sp.addChild(shd3);
						sp.addChild(makeTF(text3, fs3, col3, true));
						vy = isCrit ? -3.8 : -2.8; vx = 0; ttl = 90;
						break;
					}

					default: return;
				}

				_ours[sp] = true;
				pMC.addChild(sp);
				_nums.push({ sp: sp, pMC: pMC, vy: vy, vx: vx,
							 ttl: ttl, maxTtl: ttl, gravity: useGravity });
			}
			catch (e:Error) {}
		}

		private function updateFloating():void
		{
			var i:int = _nums.length - 1;
			while (i >= 0)
			{
				var n:Object = _nums[i];
				n.sp.y += n.vy;
				n.sp.x += n.vx;
				if (n.gravity) n.vy += 0.06;
				else           n.vy *= 0.97;

				n.sp.alpha = (n.ttl <= FADE_FRAMES) ? (n.ttl / FADE_FRAMES) : 1.0;

				n.ttl--;
				if (n.ttl <= 0)
				{
					try { n.pMC.removeChild(n.sp); } catch (e:Error) {}
					delete _ours[n.sp];
					_nums.splice(i, 1);
				}
				i--;
			}
		}

		private function clearAll():void
		{
			for (var i:int = _nums.length - 1; i >= 0; i--)
			{
				try { _nums[i].pMC.removeChild(_nums[i].sp); } catch (e:Error) {}
				delete _ours[_nums[i].sp];
			}
			_nums = [];
		}

		private function makeTF(text:String, fs:int, color:uint, bold:Boolean):TextField
		{
			var tf:TextField = new TextField();
			tf.selectable        = false;
			tf.mouseEnabled      = false;
			tf.autoSize          = TextFieldAutoSize.LEFT;
			tf.defaultTextFormat = new TextFormat("Arial", fs, color, bold);
			tf.text              = text;
			return tf;
		}
	}
}
