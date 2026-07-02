package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.geom.ColorTransform;

	public class DisableShadows extends Module
	{
		private static const HIDE:ColorTransform = new ColorTransform(1, 1, 1, 0);
		private static const SHOW:ColorTransform = new ColorTransform();

		public function DisableShadows()
		{
			super("DisableShadows");
		}

		override public function onToggle(game:*):void
		{
			var hide:Boolean = enabled;

			for (var aid:* in game.world.avatars)
			{
				var avatar:* = game.world.avatars[aid];
				try
				{
					if (!avatar || !avatar.pMC) continue;
					// Direct known path from HidePlayers.as
					killShadow(avatar.pMC.shadow, hide);
					// Recursive sweep catches any other named shadow children
					sweepShadows(avatar.pMC, hide);
				}
				catch (e:Error) {}
			}

			for (var mid:* in game.world.monsters)
			{
				var monster:* = game.world.monsters[mid];
				try
				{
					if (!monster || !monster.pMC) continue;
					killShadow(monster.pMC.shadow, hide);
					sweepShadows(monster.pMC, hide);
				}
				catch (e:Error) {}
			}
		}

		override public function onFrame(game:*):void
		{
			onToggle(game);
		}

		private function killShadow(obj:*, hide:Boolean):void
		{
			if (!obj) return;
			try
			{
				obj.visible = !hide;
				obj.alpha   = hide ? 0 : 1;
				// scaleX/Y=0 makes it physically zero-sized — survives any alpha/visible reset by the game
				obj.scaleX  = hide ? 0 : 1;
				obj.scaleY  = hide ? 0 : 1;
				obj.transform.colorTransform = hide ? HIDE : SHOW;
			}
			catch (e:Error) {}
		}

		private function sweepShadows(obj:DisplayObject, hide:Boolean):void
		{
			try
			{
				var n:String = obj.name ? obj.name.toLowerCase() : "";
				if (n.indexOf("shadow") != -1)
				{
					killShadow(obj, hide);
					return;
				}
				if (obj is DisplayObjectContainer)
				{
					var doc:DisplayObjectContainer = DisplayObjectContainer(obj);
					for (var i:int = 0; i < doc.numChildren; i++)
						sweepShadows(doc.getChildAt(i), hide);
				}
			}
			catch (e:Error) {}
		}
	}
}
