package skua.module
{
	import flash.display.StageQuality;

	public class AutoQuality extends Module
	{
		private static var _pattern:RegExp = /bludrutbrawl/gi;
		private var _inPvP:Boolean = false;

		public function AutoQuality()
		{
			super("AutoQuality");
			this.enabled = true;
		}

		override public function onFrame(game:*):void
		{
			try
			{
				var text:String = String(game.ui.mcInterface.areaList.title.t1.text);
				var isPvP:Boolean = _pattern.test(text);
				_pattern.lastIndex = 0;
				if (isPvP == _inPvP) return;
				_inPvP = isPvP;
				game.stage.quality = isPvP ? StageQuality.LOW : StageQuality.HIGH;
			}
			catch (e:Error) {}
		}
	}
}
