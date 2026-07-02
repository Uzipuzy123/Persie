package skua.module
{
	import flash.utils.getTimer;

	public class FrameTimeMonitor
	{
		private static var _lastTime:int    = 0;
		private static var _buffer:Array    = [];
		private static const MAX:int        = 90; // ~1.5 s at 60 fps

		public static function tick():void
		{
			var now:int = getTimer();
			if (_lastTime > 0)
			{
				var delta:int = now - _lastTime;
				if (delta > 0 && delta < 500)
				{
					_buffer.push(delta);
					if (_buffer.length > MAX)
						_buffer.shift();
				}
			}
			_lastTime = now;
		}

		public static function getStats():String
		{
			if (_buffer.length == 0)
				return '{"avg":0,"min":0,"max":0,"fps":0}';

			var sum:Number = 0;
			var min:Number = _buffer[0];
			var max:Number = _buffer[0];
			var n:int      = _buffer.length;

			for (var i:int = 0; i < n; i++)
			{
				var v:Number = _buffer[i];
				sum += v;
				if (v < min) min = v;
				if (v > max) max = v;
			}

			var avg:Number = sum / n;
			var fps:int    = avg > 0 ? int(Math.round(1000 / avg)) : 0;

			return '{"avg":' + (Math.round(avg * 10) / 10)
				 + ',"min":' + min
				 + ',"max":' + max
				 + ',"fps":' + fps + '}';
		}
	}
}
