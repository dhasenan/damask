module dmud.commands;

import std.string;

import dmud.domain;
import dmud.player;
import dmud.except;
import dmud.log;
import dmud.time;

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
	final void act(MudObj self, string target) {
		//		if (self.generation != _generation) {
		//			return;
		//		}
		doAct(self, target);
	}

	// How long it takes to do this.
	Span duration = {1};
	
	abstract void doAct(MudObj self, string target);

	bool applicable(MudObj obj) { return true; }
}

class Quit : Command {
	override void doAct(MudObj self, string target) {
		logger.infof("%s is quitting", self.name);
		auto mob = cast(Player) self;
		if (mob && mob.telnet) {
			mob.writeln("Be seeing you.");
			mob.telnet.close;
		}
	}
}

class Look : Command {
	override void doAct(MudObj self, string target) {
		target = target.strip;
		dmud.log.logger.infof("look: looking at [%s] (%d)", target, target.length);
		auto mob = cast(Mob)self;
		dmud.log.logger.info("after the cast");
		if (!mob) {
			dmud.log.logger.info("not the mob");
			// Zones, rooms, items, etc can't look at things.
			return;
		}
		dmud.log.logger.info("have a mob");
		if (target == "") {
			dmud.log.logger.info("looking at the room");
			if (mob.room) {
				dmud.log.logger.info("we do have a room");
				mob.writeln(mob.room.lookAt(mob));
			} else {
				dmud.log.logger.info("no room");
				mob.writeln("You are in an empty void.");
			}
			return;
		}
		dmud.log.logger.info("looking for an item");
		// We need to locate the mudobj in question.
		// It might be in the player's inventory or in the room.
		foreach (item; mob.inventory) {
			if (item.identifiedBy(target)) {
				dmud.log.logger.info("found item!");
				mob.writeln(item.lookAt(mob));
				return;
			}
		}
		dmud.log.logger.info("no match");
		mob.writeln("I don't see that here.");
	}
}

class News : Command {
	override void doAct(MudObj self, string target) {
		//auto n = World.current.news.filter!(x => )
	}
}

static this() {
	Command.register(new Look(), "look", "l");
	Command.register(new Quit(), "quit");
}
