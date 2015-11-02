module dmud.player;

import core.thread;
import std.concurrency;
import std.digest.sha;
import std.string;
import std.stdio;

import dmud.domain;
import dmud.container;
import dmud.telnet_socket;

const longString = "On the other hand, we denounce with righteous indignation and dislike men who are so beguiled and demoralized by the charms of pleasure of the moment, so blinded by desire, that they cannot foresee the pain and trouble that are bound to ensue; and equal blame belongs to those who fail in their duty through weakness of will, which is the same as saying through shrinking from toil and pain. These cases are perfectly simple and easy to distinguish. In a free hour, when our power of choice is untrammelled and when nothing prevents our being able to do what we like best, every pleasure is to be welcomed and every pain avoided. But in certain circumstances and owing to the claims of duty or the obligations of business it will frequently occur that pleasures have to be repudiated and annoyances accepted. The wise man therefore always holds in these matters to this principle of selection: he rejects pleasures to secure other greater pleasures, or else he endures pains to avoid worse pains.";

class PlayerInputBehavior : IBehavior {
	Queue!string commands;
	IBehavior child;
	Command next(Time now) { return null; }
}

abstract class InputProcessor {
	private Fiber _runFiber;
	
	final void run(TelnetSocket telnet) {
		assert(!!scheduler);
		writeln("about to start input task");
		scheduler.spawn({
			writeln("about to run input processor");
			_runFiber = Fiber.getThis();
			doRun(telnet);
			writeln("input task finished");
			_runFiber = null;
		});
	}
	
	void interrupt() {
		throw new Exception("this option is not yet implemented");
	}
	
	abstract void doRun(TelnetSocket telnet);
}

class WelcomeProcessor : InputProcessor {
	override void doRun(TelnetSocket telnet) {
		writeln("starting welcome!");
		while (!telnet.closed) {
			telnet.write("Enter your character's name, or \"new\" for a new character: ");
			auto first = telnet.readLine;
			writeln("person entered: [", first, "]");
			if (first != first.strip) {
				writeln("error: readLine didn't strip");
			}
			if (first == "quit") {
				writeln("quitting");
				telnet.close();
				return;
			}
			if (first == "new") {
				writeln("new player");
				registerNewPlayer(telnet);
				writeln("done with registration bits");
				return;
			}
			auto p = first in Player.byName;
			if (!p) {
				telnet.writeln(format("Sorry, no player by that name exists."));
				continue;
			}
			auto player = *p;
			telnet.write(format("Enter password for %s: ", first));
			while (!telnet.closed) {
				auto pass = telnet.readLine;
				if (player.passwordEqual(pass)) {
					break;
				}
				telnet.writeln("Sorry, that's not the right password. Try again.");
			}
			// You've logged in! \o/
			telnet.writeln(format("Welcome back to Damask, %s.", player.name));
		}
		
	}
	
	void registerNewPlayer(TelnetSocket telnet) {
		string name;
		telnet.write("What name do you want? ");
		while (!telnet.closed) {
			name = telnet.readLine.strip;
			if (name in Player.byName) {
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
		auto p = new Player();
		p.password = pass;
		p.name = name;
		Player.byName[name] = p;
		telnet.writeln(format("Welcome to Damask, %s.", name));
		return;
	}
	
	void gmcp(string raw) {
		
	}
}

/// A player. Not necessarily in the game right now.
class Player {
	static Player[string] byName;
	string name;
	ubyte[] passwordHash;
	bool admin;
	Mob mob;  /// The mob this player controls.
	bool playing;
	TelnetSocket telnet;

	void password(string value) {
		auto hash = sha256Of(value);
		passwordHash.length = hash.length;
		passwordHash[0..$] = hash[0..$];
	}

	bool passwordEqual(string value) {
		auto hash = sha256Of(value);
		return hash[0..$] == passwordHash;
	}
	
	bool login(TelnetSocket socket, string username, string pass) {
		if (!name && !passwordHash) {
			password = pass;
			name = username;
			mob = new Mob();
			mob.name = username;
			mob.id = "/players/" ~ name;
			mob.description = "A new player. Be gentle.";
			mob.sink = telnet;
			return true;
		}
		if (name == username && passwordEqual(pass)) {
			this.telnet = socket;
			if (!mob) {
				mob = new Mob();
				mob.name = username;
				mob.id = "/players/" ~ name;
				mob.description = "A new player. Be gentle.";
				mob.sink = telnet;
			}
			return true;
		}
		return false;
	}
}
