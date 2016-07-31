module dmud.player;

import std.digest.sha;
import std.experimental.logger;
import std.format;
import std.string;
import std.stdio;
import std.typecons;
import std.uni;

import dmud.commands;
import dmud.component;
import dmud.domain;
import dmud.container;
import dmud.telnet_socket;
import dmud.time;
import dmud.util;

@safe:

class PlayerInputBehavior : Behavior {
	Queue!string commands;
	Behavior child;
	Command next(Time now) { return null; }
}

abstract class InputProcessor {
	private Fiber _runFiber;

	final void run(TelnetSocket telnet) {
		spawn({
				_runFiber = getRunning;
				doRun(telnet);
				_runFiber = null;
			});
	}

	void interrupt() {
		throw new Exception("this option is not yet implemented");
	}

	abstract void doRun(TelnetSocket telnet);
}

auto splitOnce(string str) {
	foreach (int i, dchar d; str) {
		if (d.isWhite) {
			return tuple!("head", "tail")(str[0..i], str[i..$].stripLeft);
		}
	}
	return tuple!("head", "tail")(str, "");
}

class PlayerBehavior : Behavior {
	Entity entity;
	Player player;
	TelnetSocket telnet;

	this(Entity p, TelnetSocket sock) {
		entity = p;
		player = p.get!Player;
		telnet = sock;
	}

	void run() {
		sharedLog.info("starting player behavior");
		writeln("starting player behavior!!");
		mainLoop:
		while (!telnet.closed) {
			auto line = telnet.readLine.stripRight;
			auto parts = line.splitOnce;
			if (parts.head.length == 0) {
				continue;
			}
			sharedLog.infof("player command: [%s] [%s]", parts.head, parts.tail);
			auto tail = parts.tail.strip.toLower;
			auto mo = entity.get!MudObj;

			// Room exits take priority.
			if (mo.containing != None) {
				auto room = mo.containing.get!Room;
				foreach (exit; room.exits) {
					if (exit.identifiedBy(parts.head)) {
						auto next = exit.target.get!Room;
						if (!next) {
							sharedLog.error("exit %s in room %s leads to %s, which is not a room", exit.name,
									mo.containing, exit.target);
							telnet.writeln("You try to go that way but something solid blocks your way.");
							continue mainLoop;
						}
						mo.containing = exit.target;
						telnet.writeln(next.lookAt(entity));
						telnet.writeln("");
						continue mainLoop;
					}
				}
			}

			// TODO: aliases
			// TODO: item- and room-specific commands
			auto commandsPtr = parts.head in Command.allCommands;
			if (!commandsPtr) {
				telnet.writeln("Huh?");
				telnet.writeln("");
				continue;
			}
			Command selected;
			foreach (cmd; *commandsPtr) {
				if (cmd.applicable(entity)) {
					if (selected) {
						// Two applicable commands. What do?
						sharedLog.error("Found two overlapping commands for name '%s'. Player '%s' at room " ~
							"'%s' experienced this problem. Command 1: %s. Command 2: %s.",
							parts.head, mo.name, mo.containing, selected.id, cmd.id);
						telnet.writeln("There are two or more commands matching your input.");
						telnet.writeln("I'm really confused about this, and I'm logging your situation for devs " ~
							"to investigate.");
						telnet.writeln("Hold tight, maybe try again in another room. Sorry!");
					}
					selected = cmd;
				}
			}
			if (selected) {
				selected.act(entity, parts.tail);
				telnet.writeln("");
			}
			// TODO: how long do we yield *for*?
			// Need to create a scheduler, command tells how long it takes, etc.
			yield;
		}
	}
}

class WelcomeProcessor : InputProcessor {
	Player player;
	InputProcessor next;

	override void doRun(TelnetSocket telnet) {
		while (!telnet.closed) {
			telnet.write("Enter your character's name, or \"new\" for a new character: ");
			auto first = telnet.readLine;
			if (first != first.strip) {
				writeln("error: readLine didn't strip");
			}
			if (first == "quit") {
				writeln("quitting");
				telnet.close();
				return;
			}
			if (first == "new") {
				registerNewPlayer(telnet);
				return;
			}
			auto p = Player.loadForInfo(first);
			if (!p) {
				telnet.writeln(format("Sorry, no player by that name exists."));
				continue;
			}
			telnet.write(format("Enter password for %s: ", first));
			while (!telnet.closed) {
				auto pass = telnet.readLine;
				if (p.passwordEqual(pass)) {
					break;
				}
				telnet.writeln("Sorry, that's not the right password. Try again.");
			}
			// You've logged in! \o/
			// We *should* have reloaded your character from the database.
			auto mo = p.entity.get!MudObj;
			auto w = world.get!World;
			telnet.writeln(format("Welcome back to %s, %s.", w.name, mo.name));
			startPlayer(p, telnet);
			return;
		}
	}

	void startPlayer(Player player, TelnetSocket telnet) {
		this.player = player;
		auto w = world.get!World;
		if (w is null) {
			telnet.writeln("Oh no! No world is available for you to inhabit.");
			telnet.writeln("Please come back when we're a little more together.");
			telnet.close;
			sharedLog.error("player tried to log in but there was no world for them");
			return;
		}
		if (w.banner) telnet.writeln(w.banner);
		auto behavior = new PlayerBehavior(player.entity, telnet);
		ComponentManager.instance.add(player.entity, player);
		spawn(&behavior.run);
	}

	void registerNewPlayer(TelnetSocket telnet) {
		string name;
		telnet.write("What name do you want? ");
		while (!telnet.closed) {
			name = telnet.readLine.strip;
			if (Player.loadForInfo(name)) {
				telnet.write("That name is already taken. Try again. ");
				continue;
			}
			break;
		}
		telnet.writeln(format("Okay, we're calling you %s.", name));
		string pass;
		while (!telnet.closed) {
			// TODO: validation -- no punctuation, numbers, etc
			telnet.write("Enter your password: ");
			pass = telnet.readLine();
			telnet.write("Enter your password again: ");
			auto pass2 = telnet.readLine();
			if (pass == pass2) {
				break;
			} else {
				telnet.writeln("Sorry, your passwords didn't match.");
			}
		}
		auto w = world.get!World;
		if (w is null) {
			telnet.writeln("Oh no! No world is available for you to inhabit.");
			telnet.writeln("Please come back when we're a little more together.");
			telnet.close;
			error("player tried to log in but there was no world for them");
			return;
		}
		auto p = Player.create(name, pass, telnet);
		telnet.writeln(format("Welcome to %s, %s.", w.name, name));
		startPlayer(p.get!Player, telnet);
	}

	void gmcp(string raw) {
	}
}

/// A player. Not necessarily in the game right now.
class Player : Component {
	private static Player[string] _byName;

	// TODO: real persistence
	static void loadForLogin(Entity entity, TelnetSocket socket) {
		assert(false, "not yet implemented");
	}

	static Player loadForInfo(string name) {
		if (auto p = name in _byName) {
			return *p;
		}
		return null;
	}

	static Entity create(string name, string pass, TelnetSocket socket) {
		// I need a mudobj, a mob (maybe), and news reading thing.
		auto entity = ComponentManager.instance.next;
		entity.add!PlayerNewsStatus;
		with (entity.add!Writer) {telnet = socket;}
		auto player = entity.add!Player;
		player.name = name;
		player.password = pass;
		_byName[name.toLower] = player;
		auto mob = entity.add!Mob;
		auto mo = entity.add!MudObj;
		mo.name = name;
		mo.description = "A faceless horror from the Abyss.";
		_byName[name] = player;
		auto w = world.get!World;
		if (w) {
			mo.containing = w.startingRoom;
		}
		return entity;
	}

	string name;
	ubyte[] passwordHash;
	bool admin;

	void password(string value) {
		auto hash = sha256Of(value);
		passwordHash.length = hash.length;
		passwordHash[0..$] = hash[0..$];
	}

	bool passwordEqual(string value) {
		auto hash = sha256Of(value);
		return hash[0..$] == passwordHash;
	}
}
