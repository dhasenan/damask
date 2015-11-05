module dmud.app;

import dmud.log;
import dmud.telnet_socket;
import dmud.domain;
import dmud.loader;
import dmud.player;
import dmud.server;

import core.thread;
import std.concurrency;
import std.experimental.logger;
import std.stdio;
import std.socket;

int main(string[] args)
{
	// Set up logging!
	auto log = new MultiLogger();
	log.insertLogger("stdout", new FileLogger(std.stdio.stdout, LogLevel.trace));
	log.insertLogger("file", new FileLogger("dmud.log", LogLevel.info));
	dmud.log.logger = log;
	World.current = load("");
	ushort port = 5005;
	scheduler = new FiberScheduler();
	// TODO ipv6 support? (pretty much means listen on two sockets, one ipv4 and one ipv6)
	auto server = new Server(port);
	logger.infof("listening on port %d", port);
	// Start the scheduler (by giving it an empty task).
	scheduler.start(() {});
	return 0;
}
