module dmud.app;

import dmud.telnet_socket;
import dmud.component;
import dmud.db;
import dmud.domain;
import dmud.loader;
import dmud.player;
import dmud.server;

import core.thread;
import std.algorithm;
import std.concurrency;
import std.experimental.logger;
import std.stdio;
import std.socket;
import etc.linux.memoryerror;

@trusted void memoryErrorStart() {
	// Set up segfault stacktraces.
	static if (is(typeof(registerMemoryErrorHandler))) {
		registerMemoryErrorHandler();
	}
}

@trusted void setupScheduler() {
	scheduler = new FiberScheduler();
}

@trusted void startScheduler() {
	// Start the scheduler (by giving it an empty task).
	scheduler.start(() {});
}

@trusted void setupLogging() {
	auto log = new MultiLogger();
	log.insertLogger("stdout", new FileLogger(stdout));
	log.insertLogger("file", new FileLogger("dmud.log"));
	sharedLog = cast(typeof(sharedLog)) log;
}

//@safe:
int main(string[] args)
{
	memoryErrorStart;
	setupLogging;

  import dmud.citygen;

  auto db = new Db("mud.sqlite");
  db.init;

  if (args.canFind(`gen`)) {
    auto w = world.add!World;
    w.name = "The Mud";
    w.banner = "Welcome!";
    new IslandGen().generate(true);
    foreach (i; 0..5) {
      new IslandGen().generate(false);
    }
    save(db, ComponentManager.instance);
  } else {
    load(db, ComponentManager.instance);
  }

	setupScheduler;
	ushort port = 5005;
	auto server = new Server(port, db);
	info("listening on port ", port);
	startScheduler;

	return 0;
}
