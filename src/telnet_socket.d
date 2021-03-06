module dmud.telnet_socket;

import dmud.component;
import dmud.domain;
import dmud.util;

import core.thread;

import std.algorithm;
import std.container.dlist;
import std.encoding;
import std.signals;
import std.socket;
import std.string;
import std.uni;

@safe:

@trusted struct Event(T...) {
	mixin Signal!T;
}

// @trusted for encoding.canEncode
void wrap()(string value, int width, const EncodingScheme encoding, void delegate(dchar) @safe output) @trusted
{
	value = value.normalize!NFD;
	auto len = 0;
	dchar last = dchar.max;
	auto lineWidth = 0;
	auto start = 0;
	size_t lastSplit = 0;
	size_t lineStart = 0;
	size_t atLastSplit = 0;
	foreach (int i, dchar v; value) {
		if (encoding.canEncode(v)) {
			if (v == '\n') {
				if (i > 0) {
					foreach (dchar d; value[lineStart..i]) {
						output(d);
					}
				}
				if (i <= 0 || value[i-1] != '\r') {
					output('\r');
				}
				output(v);
				lineWidth = 0;
				lineStart = i + 1;
				lastSplit = lineStart;
				atLastSplit = 0;
				continue;
			}
			if (unicode.Grapheme_Base[v]) {
				lineWidth++;
				if (lineWidth < width - 1) {
					if (unicode.White_Space[v]) {
						lastSplit = i;
						atLastSplit = lineWidth;
					}
					continue;
				}
				if (unicode.White_Space[v]) {
					// Omit this.
					foreach (dchar d; value[lineStart..i-1]) {
						output(d);
					}
					lineStart = i + 1;
					lineWidth = 0;
					atLastSplit = 0;
				} else if (lastSplit > lineStart) {
					foreach (dchar d; value[lineStart..lastSplit]) {
						output(d);
					}
					lineStart = lastSplit + 1;
					lineWidth -= atLastSplit;
					atLastSplit = 0;
				} else {
					// TODO: this is wrong! We need to hyphenate at the last grapheme base!
					foreach (dchar d; value[lineStart..i-1]) {
						output(d);
					}
					output('-');
				}
				output('\r');
				output('\n');
				lineWidth = 0;
			}
		}
	}

	if (lineStart < value.length - 1) {
		// We have a trailing portion.
		foreach (dchar v; value[lineStart..$]) {
			output(v);
		}
	}
}

@safe:

@trusted string safeDecodeString(const EncodingScheme encoding, const(ubyte)[] value) {
	// Trusted because safeDecode isn't safe and because, when we create a char[] locally, we aren't
	// allowed to say it's a string.
	auto c = new char[value.length];
	c.length = 0;
	while (value && value.length) {
		auto d = encoding.safeDecode(value);
		if (d != INVALID_SEQUENCE && d != 0) {
			c ~= d;
		}
	}
	return cast(string)c;
}

@system unittest {
	ubyte[] b = [84, 111, 100, 100, 13, 10];
	assert(safeDecodeString(EncodingScheme.create("ascii"), b) == "Todd\r\n");
}

ubyte[] toBytes(const EncodingScheme encoding, string str) @trusted // trusted until std.encoding changes
{
	size_t len = 0;
	foreach (dchar d; str) {
		len += encoding.encodedLength(d);
	}
	auto a = new ubyte[len];
	auto b = a;
	foreach (dchar d; str) {
		auto s = encoding.encode(d, b);
		b = b[s..$];
	}
	return a;
}

ubyte[] toAscii(string str) {
	return toBytes(ascii, str);
}

void debugWrite(string tag, const ubyte[] v) {
	import std.stdio : write;
	write(tag);
	write(": [");
	for (int i = 0; i < v.length; i++) {
		if (i) {
			write(", ");
		}
		write(v[i]);
	}
	write("]\n");
}

unittest {
	string s;
	auto target = "On the other hand, we denounce with righteous indignation and dislike men who are so beguiled and demoralized";
	wrap(target, 25, ascii, (dchar d) @safe { s ~= d; });
	assert(s == "On the other hand, we\r\ndenounce with righteous\r\nindignation and dislike\r\nmen who are so beguiled\r\nand demoralized");

	auto endsWithNewline = "On the first day\n";
	s = "";
	wrap(endsWithNewline, 25, ascii, (dchar d) @safe { s ~= d; });
	assert(s == "On the first day\r\n");
}


class Writer : Component {
	this() { canSave = false; }
	TelnetSocket telnet;

	void write(string value) {
		if (telnet) {
			telnet.write(value);
		}
	}

	void writeln(string value) {
		if (telnet) {
			telnet.writeln(value);
		}
	}
}


/// A telnet socket is a socket that can communicate via telnet.
class TelnetSocket {
	bool closed;

	private {
		Socket _sock;
		EncodingScheme _encoding;
		ubyte[] _writeBuffer;
		string _terminalType;
		uint _width = 80, _height = 23;
		bool _shouldGmcp;
		bool _echo = true;

		static ubyte[] _charsetGreetingCache;
		static EncodingScheme[string] _encodings;
		static ubyte[] _charsetGreeting() {
			if (_charsetGreetingCache) return _charsetGreetingCache;
			_encodings = [
				"utf-8": utf8,
				"ascii": ascii,
				"us-ascii": ascii,
				"iso-8859-1": iso8859_1,
				"utf-32le": utf32,
				];
			int len = 0;
			auto parts = new ubyte[][_encodings.length];
			size_t i = 0;
			foreach (string k, EncodingScheme v; _encodings) {
				parts[i] = toBytes(ascii, k);
				len++;
				len += parts[i].length;
				i++;
			}
			_charsetGreetingCache = new ubyte[6 + len];
			_charsetGreetingCache[0..4] = [IAC, SB, cast(ubyte)Charset, cast(ubyte)1];
			ubyte sep = 59;	// ASCII semicolon ';'
			auto s = 4;
			foreach (part; parts) {
				_charsetGreetingCache[s] = sep;
				s++;
				_charsetGreetingCache[s..s+part.length] = part[0..$];
				s += part.length;
			}
			_charsetGreetingCache[$-2] = IAC;
			_charsetGreetingCache[$-1] = SB;
			return _charsetGreetingCache;
		}
	}

	this(Socket socket, size_t bufferSize = 1024) {
		_sock = socket;
		_sock.blocking = false;
		_encoding = ascii;
		_writeBuffer = new ubyte[bufferSize];
		onConnect();
	}

	string terminalType() { return _terminalType; }

	void writeln(string value) {
		if (value.endsWith("\n")) {
			write(value);
		} else {
			write(value ~ "\r\n");
		}
	}

	void write(string value) @trusted /* for std.encoding */ {
		auto len = 0;
		void output(dchar v) @trusted {
			auto c = _encoding.encodedLength(v);
			if (c + len >= _writeBuffer.length) {
				// TODO: we are optimistically assuming that send() will
				// always succeed. If the client isn't acknowledging
				// messages, we'll queue up a lot of stuff in the buffer
				// and writes will start to fail. This will take 16k by
				// default, though. (We *can* increase this number.)
				_sock.send(_writeBuffer[0..len]);
				len = 0;
			}
			len += _encoding.encode(v, _writeBuffer[len..$]);
		}
		wrap(value, _width, _encoding, &output);
		if (len > 0) {
			_sock.send(_writeBuffer[0..len]);
			// Kinda pointless, but it's here to defend in case I refactor carelessly.
			len = 0;
		}
	}

	void close() {
		closed = true;
		_sock.close();
	}

	enum : ubyte {
		SE = 240,
		NOP = 241,
		DM = 242,
		BRK = 243,
		IP = 244,
		AO = 245,
		AYT = 246,
		EC = 247,
		EL = 248,
		GA = 249,
		SB = 250,
		WILL = 251,
		WONT = 252,
		DO = 253,
		DONT = 254,
		IAC = 255,
	}

	private DList!string _dataQueue;

	const MAX_LINE_LENGTH = 1024;


	// TODO: This busy-waits until the socket has data. Instead make a
	// fiber scheduler that is IO-aware and can wait until a socket has
	// data available for reading.
	string readLine(bool trim = true) @trusted {
		string s = "";
		while (!closed) {
			while (_dataQueue.empty) {
				yield();
			}
			auto item = _dataQueue.front;
			_dataQueue.removeFront();
			debugWrite("datum", cast(ubyte[])item);
			auto i = item.indexOf('\n');
			if (i >= 0) {
				s ~= item[0..i];
				_dataQueue.insertFront(item[i + 1 .. $]);
				if (trim) {
					s = s.strip;
				}
				return s;
			}
			s ~= item;
			if (s.length > MAX_LINE_LENGTH) {
				if (trim) {
					s = s.strip;
				}
				return s;
			}
		}
		return "";
	}

	// TODO: This busy-waits. Make better socket-aware scheduler.
	void run() {
		auto readBuffer = new ubyte[_writeBuffer.length];
		auto parseBuffer = new ubyte[_writeBuffer.length];
		size_t s = 0;

		int a = -1;
		int b = -1;
		int c = 0;
		bool inExtendedCommand = false;
		int commandType = -1;
		while (true) {
			scope (exit) yield();
			auto received = _sock.receive(readBuffer);
			if (received == 0) {
				close();
				return;
			}
			if (received < 0) {
				continue;
			}
			debugWrite("raw", readBuffer[0..received]);
			for (int i = 0; i < received; i++) {
				a = b;
				b = c;
				c = readBuffer[i];
				if (c == IAC) {
					if (b == IAC) {
						parseBuffer[s] = IAC;
						s++;
						// Null out this and the previous so we can correctly process a long series of IACs.
						// For instance, IAC IAC IAC WILL NAWS should be interpreted as 0xFF (data) + WILL NAWS.
						// If we left the IAC byte in the history slots, this would not be handled correctly.
						b = -1;
						c = -1;
					}
					continue;
				}
				if (b == IAC) {
					// There are only a few possibilities.
					// 1. IAC IAC -- handled above; won't ever get here.
					// 2. IAC [WILL|WONT|DO|DONT] -- handle next round
					// 3. IAC [short code] -- effectively deprecated.
					// 4. IAC SB [code] ... IAC SE -- handle next round
					// Anyway, all we can do is flush the parse buffer.
					onRead(commandType, parseBuffer[0..s + 1]);
					s = 0;
					continue;
				}
				if (a == IAC) {
					switch (b) {
						case WILL:
						case WONT:
						case DO:
						case DONT:
							// Handle option negotiation.
							onActive(c, cast(ubyte)b);
							continue;
						case SB:
							inExtendedCommand = true;
							commandType = c;
							continue;
						case SE:
							inExtendedCommand = false;
							commandType = -1;
							continue;
						default:
					}
				}
				// We haven't found any commands. This must be a data item.
				parseBuffer[s] = cast(ubyte)c;
				s++;
			}
			if (commandType == -1) {
				onRead(commandType, parseBuffer[0..s]);
				s = 0;
			}
		}
	}

	Event!(TelnetSocket, string) data;

	enum : int {
		Echo = 1,
		SuppressGoAhead = 3,
		TerminalType = 24,
		EndOfRecord = 25,
		WindowSize = 31,
		Charset = 42,
		// Mud Server Status Protocol: transmit some data about server status to clients.
		MSSP = 70,
		/// Mud Client Compression Protocol: turns on gzip for server output.
		MCCP = 86,
		/// Mud Sound Protocol: embeds sound effects in the data stream.
		MSP = 90,
		/// Mud Extension Protocol: once enabled, you can use HTML-style tags in the content.
		MXP = 91,
		/// Generic Mud Communication Protocol: transmit parseable data between client and server.
		GMCP = 201
	}

		private bool isValid(AsciiString s) @trusted
		{
				import std.encoding : isValid;
				return std.encoding.isValid(s);
		}

		private void transcode(immutable(AsciiString) src, out string dest) @trusted
		{
				import std.encoding : transcode;
				std.encoding.transcode(src, dest);
		}

	private void onRead(int type, ubyte[] value) {
		switch (type) {
			case -1:
				auto str = safeDecodeString(_encoding, value);
				_dataQueue.insertBack(str);
				break;
			case TerminalType:
				auto s = cast(AsciiString)value[1..$];
				if (s && isValid(s)) {
					transcode(s, _terminalType);
				}
				break;
			case WindowSize:
				if (value.length == 4) {
					_width = max(value[0] << 8 + value[1], 40);
					// We don't really use height for anything, but...
					_height = value[2] << 8 + value[3];
				}
				break;
			case Charset:
				if (value[0] == 2) {
					// We're accepting a character set!
					auto name = cast(AsciiString)value[1..$];
					if (name && isValid(name)) {
						string nameStr;
						transcode(name, nameStr);
						auto p = nameStr in _encodings;
						if (p) {
							_encoding = *p;
						}
					}
				}
				break;
			default:
		}
	}

	private void onActive(int type, ubyte should) {
		switch (type) {
			case Charset:
				if (should == DO) {
					// Hard-coded list of supported types!
					writeln("sending charset greeting");
					debugWrite("greeting", _charsetGreeting);
					_sock.send(_charsetGreeting);
				}
				break;
			case GMCP:
				break;
			default:
		}
	}

	private void onConnect() {
		/*
		 _sock.send([
		 IAC, WILL, cast(ubyte)SuppressGoAhead,
		 IAC, DO, cast(ubyte)SuppressGoAhead,
		 IAC, DO, cast(ubyte)WindowSize,
		 IAC, WILL, cast(ubyte)Charset,
		 IAC, DO, cast(ubyte)TerminalType,
		 IAC, WILL, cast(ubyte)GMCP,
		 IAC, WILL, cast(ubyte)MSSP,
		 IAC, WILL, cast(ubyte)EndOfRecord,
		 ]);
		 */
	}
}
