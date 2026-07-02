package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.MovieClip;

	public class StopAnimations extends Module
	{
		public function StopAnimations()
		{
			super("StopAnimations");
		}

		override public function onToggle(game:*):void
		{
			try { sweep(game.world.map, enabled); } catch (e:Error) {}
		}

		private function sweep(obj:DisplayObject, doStop:Boolean):void
		{
			try
			{
				if (obj is MovieClip)
				{
					if (doStop) MovieClip(obj).stop();
					else        MovieClip(obj).play();
				}
				if (obj is DisplayObjectContainer)
				{
					var doc:DisplayObjectContainer = DisplayObjectContainer(obj);
					for (var i:int = 0; i < doc.numChildren; i++)
						sweep(doc.getChildAt(i), doStop);
				}
			}
			catch (e:Error) {}
		}
	}
}
