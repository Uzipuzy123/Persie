package skua.module
{
	import flash.text.TextField;

	public class HideRoomNumber extends Module
	{
		private static var _pattern:RegExp = /bludrutbrawl-\d+/gi;

		public function HideRoomNumber() { super("HideRoomNumber"); }

		override public function onFrame(game:*):void { if (enabled) apply(game); }

		private function apply(game:*):void
		{
			try
			{
				var tf:* = game.ui.mcInterface.areaList.title.t1;
				if (!tf) return;
				var s:String = String(tf.text);
				if (_pattern.test(s))
				{
					_pattern.lastIndex = 0;
					tf.text = s.replace(_pattern, "bludrutbrawl-????");
				}
				_pattern.lastIndex = 0;
			}
			catch (e:Error) {}
		}
	}
}
