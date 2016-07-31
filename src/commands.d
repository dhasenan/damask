module dmud.commands;

import std.algorithm;
import std.format;
import std.string;
import std.experimental.logger;

import dmud.component;
import dmud.domain;
import dmud.player;
import dmud.except;
import dmud.time;
import dmud.telnet_socket;

@safe:

abstract class Command {
	/// Commands indexed by their keyword.
	/// A command might appear in multiple entries -- for instance, "i", "inv", and "inventory" all map to the
	/// Inventory command.
	static Command[][string] allCommands;
	static Command[string] byId;
	static void register(Command cmd, string[] names...) {
		if (!names) {
			throw new ArgumentException("names", "commands must be registered with at least one name; failed for " ~
				cmd.classinfo.name ~ " command with id " ~ cmd.id);
		}
		if (cmd.id in byId) {
			throw new ArgumentException("cmd", "id is not unique for command of type " ~ cmd.classinfo.name ~
				" registered under name " ~ names[0]);
		}
		byId[cmd.id] = cmd;
		foreach (name; names) {
			auto c = name in allCommands;
			if (c) {
				*c ~= cmd;
			} else {
				allCommands[name] = [cmd];
			}
		}
	}

	string id() { return this.classinfo.name; }

	private int _generation;
	final void act(Entity self, string target) {
		//		if (self.generation != _generation) {
		//			return;
		//		}
		doAct(self, target);
	}

	// How long it takes to do this.
	Span duration = {1};
	
	abstract void doAct(Entity self, string target);

	bool applicable(Entity obj) { return true; }
}

class Quit : Command {
	override void doAct(Entity self, string target) {
		auto mo = self.get!MudObj;
		infof("%s is quitting", mo.name);
		auto writer = self.get!Writer;
		if (writer && writer.telnet) {
			writer.writeln("Be seeing you.");
			writer.telnet.close;
		}
	}
}

class Look : Command {
	override void doAct(Entity self, string target) {
		auto writer = self.get!Writer;
		auto mob = self.get!MudObj;
		if (!mob) {
			return;
		}
		target = target.strip;
		auto room = mob.containing.get!Room;
		if (target == "") {
			if (room) {
				writer.writeln(room.lookAt(self));
			} else {
				writer.writeln("You are in an empty void.");
			}
			return;
		}
		// We need to locate the mudobj in question.
		// It might be in the player's inventory or in the room.
		foreach (item; self.get!Inventory) {
			auto mo = item.get!(MudObj);
			if (mo.identifiedBy(target)) {
				writer.writeln(mo.lookAt(self));
				return;
			}
		}
		writer.writeln("I don't see that here.");
	}
}

class News : Command {
	override void doAct(Entity self, string target) {
		auto news = world.get!AllNews;
		auto writer = self.get!Writer;
		if (!news || !news.news) {
			writer.writeln("No news is good news!");
			return;
		}
		auto read = self.get!PlayerNewsStatus;
		foreach (ni; news.news) {
			infof("have news item %s", ni.id);
		}
		NewsItem ni;
		if (!read.lastRead) {
			ni = news.news[0];
		}
		else {
			auto lastRead = news.news.countUntil!((NewsItem x) => x.id >= read.lastRead);
			infof("news: total %s news items; player last read %s at %s", news.news.length, lastRead,
					read.lastRead);
			if (lastRead == news.news.length - 1) {
				writer.writeln("No news, only olds! Ah ha ha, I kill me.");
				return;
			}
			ni = news.news[lastRead + 1];
		}
		if (ni) {
			writer.writeln(format("News as of %s:\n%s", ni.date, ni.news));
			read.lastRead = ni.id;
		}
	}
}

static this() {
	Command.register(new Look(), "look", "l");
	Command.register(new Quit(), "quit");
	Command.register(new News(), "news");
}
