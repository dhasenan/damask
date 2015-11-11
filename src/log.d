module dmud.log;

import tango.util.log.Log;
import tango.util.log.AppendConsole;
import tango.util.log.AppendFiles;

Logger logger;

static this() {
	logger = Log.lookup("main");
	logger.level = Level.Trace;
	logger.add(new AppendConsole());
	logger.add(new AppendFiles("dmud.log", 10, 1024 * 1024 * 10));
}
