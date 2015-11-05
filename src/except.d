﻿module dmud.except;

class ArgumentException : Exception {
	this(string argument) {
		super("Invalid argument '" ~ argument ~ "'");
	}
	this(string argument, string message) {
		super("Invalid argument '" ~ argument ~ "': " ~ message);
	}
}