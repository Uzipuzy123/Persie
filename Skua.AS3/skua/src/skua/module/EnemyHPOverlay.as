package skua.module
{
	import flash.display.DisplayObject;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	public class EnemyHPOverlay extends Module
	{
		private static const TAG:String = "skua_hp";

		public function EnemyHPOverlay()
		{
			super("EnemyHPOverlay");
		}

		override public function onToggle(game:*):void
		{
			if (!enabled)
				removeAll(game);
			else
				apply(game);
		}

		override public function onFrame(game:*):void
		{
			apply(game);
		}

		private function apply(game:*):void
		{
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			for (var aid:* in game.world.avatars)
			{
				var avatar:* = game.world.avatars[aid];
				try
				{
					if (!avatar || !avatar.pMC || !avatar.dataLeaf) continue;

					// Reuse existing label or create a new one.
					var tf:TextField = avatar.pMC.getChildByName(TAG) as TextField;
					if (tf == null)
					{
						tf = makeField(avatar, myTeam);
						avatar.pMC.addChild(tf);
					}

					var hp:int    = int(avatar.dataLeaf.intHP);
					var maxHP:int = int(avatar.dataLeaf.intHPMax);
					if (maxHP == 0) maxHP = int(avatar.dataLeaf.intMaxHP);
					if (maxHP == 0) maxHP = int(avatar.dataLeaf.nMaxHP);

					tf.text = hp + " / " + (maxHP > 0 ? String(maxHP) : "?");

					// Centre horizontally above the pMC origin (feet).
					tf.x = -tf.width * 0.5;

					// Position above the name plate if it exists, otherwise fixed offset.
					try   { tf.y = avatar.pMC.pname.y - tf.height - 4; }
					catch (e2:Error) { tf.y = -120; }
				}
				catch (e:Error) {}
			}
		}

		private function makeField(avatar:*, myTeam:*):TextField
		{
			var color:uint = 0xFFFFFF;
			if (!avatar.isMyAvatar)
			{
				try
				{
					var theirTeam:* = avatar.objData.strTeam;
					if (myTeam != null && theirTeam != null)
						color = (myTeam != theirTeam) ? 0xFF4444 : 0x44FF44;
				}
				catch (e:Error) {}
			}

			var fmt:TextFormat = new TextFormat("Arial", 11, color, true);
			var tf:TextField   = new TextField();
			tf.name              = TAG;
			tf.defaultTextFormat = fmt;
			tf.autoSize          = TextFieldAutoSize.CENTER;
			tf.selectable        = false;
			tf.mouseEnabled      = false;
			return tf;
		}

		private function removeAll(game:*):void
		{
			try
			{
				for (var aid:* in game.world.avatars)
				{
					var avatar:* = game.world.avatars[aid];
					try
					{
						if (!avatar || !avatar.pMC) continue;
						var tf:DisplayObject = avatar.pMC.getChildByName(TAG);
						if (tf) avatar.pMC.removeChild(tf);
					}
					catch (e:Error) {}
				}
			}
			catch (e:Error) {}
		}
	}
}
