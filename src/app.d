module dmud.app;

import dmud.telnet_socket;
import dmud.domain;
import dmud.player;
import dmud.server;

import core.thread;
import std.concurrency;
import std.stdio;
import std.socket;

int main(string[] args)
{
	scheduler = new FiberScheduler();
	// TODO ipv6 support? (pretty much means listen on two sockets, one ipv4 and one ipv6)
	auto server = new Server(5005);
	// Start the scheduler (by giving it an empty task).
	scheduler.start(() {});
	return 0;
}
