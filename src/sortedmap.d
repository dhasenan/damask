module dmud.sortedmap;

import std.container.rbtree;
import std.functional : binaryFun;

/**
  * A SortedMap is a dictionary from Key to Value.
  *
  * It allows quick access to the lowest and highest elements in the map as well as queries for
  * ranges of elements.
  */
class SortedMap(Key, Value, alias less="a < b", bool allowDuplicates = false)
if (is(typeof(binaryFun!less(Key.init, Key.init))))
{
	import std.typecons : Tuple;
	/**
	  * The internal element type.
	  *
	  * For several reasons, it's convenient to have a key/value pair type.
	  */
	struct Elem {
		Key key;
		Value value;
		int opCmp(Elem b) inout {
			if (binaryFun!less(key, b.key)) {
				return -1;
			}
			if (binaryFun!less(b.key, key)) {
				return 1;
			}
			return 0;
		}
	}

	private RedBlackTree!(Elem, "a < b", allowDuplicates) tree;

	this() {
		tree = new typeof(tree);
	}

	/**
	  * The number of elements this map contains.
	  */
	size_t length() {
		return tree.length;
	}

	/**
	  * Whether the given key exists in this map.
	  */
	bool opIn_r(Key key) {
		return !tree.equalRange(Elem(key, Value.init)).empty;
	}

	/// ditto
	alias contains = opIn_r;

	/**
	  * Get the values in this map corresponding to the given key.
	  *
	  * If the map allows duplicates, this returns a range. Otherwise, it returns a single value or
	  * the default if it doesn't exist.
	  */
	auto opIndex(Key key) {
		static if (allowDuplicates) {
			import std.algorithm : map;
			auto r = tree.equalRange(Elem(key, Value.init));
			if (r.empty) {
				return Value.init;
			}
			return r.front.value;
		} else {
			return tree.equalRange(Elem(key, Value.init));
		}
	}

	/**
	  * Insert a value into the map with the given key.
	  *
	  * All exising items with that key will be removed. To add a new pair without removing existing
	  * items, ensure that the `allowDuplicates` parameter is set to `true` and use the `insert`
	  * method.
	  */
	void opIndexAssign(Value value, Key key) {
		Elem elem = {key: key, value: value};
		static if (allowDuplicates) {
			while (elem in tree)
			tree.removeKey(elem);
		}
		tree.insert(elem);
	}

	/**
	  * Insert the given key and value into the map.
	  */
	void insert(Key key, Value value) {
		tree.insert(Elem(key, value));
	}

	/**
	  * Remove one element with a matching key.
	  */
	void removeOne(Key key) {
		tree.removeKey(Elem(key, Value.init));
	}

	/**
	  * Fetch the first element from the map.
	  *
	  * The map retains this value.
	  */
	Elem front() {
		return tree.front;
	}

	/**
	  * Remove the first element from the map and yield its value.
	  */
	Value pop() {
		auto e = tree.front;
		tree.removeFront;
		return e.value;
	}

	void removeAll(Key key) {
		while (tree.removeKey(Elem(key, Value.init)) > 0) {
			// Just keep popping
		}
	}

	/**
	  * Retrieve everything in the map with a key less than the given key.
	  *
	  * This retrieves only values that are strictly less than the input, not less than or equal to.
	  *
	  * The return value is a range of Elem structs, exposing `key` and `value` properties.
	  *
	  * The name is in keeping with Phobos's std.container.rbtree.
	  */
	auto lowerBound(Key key) {
		auto elem = Elem(key, Value.init);
		return tree.lowerBound(elem);
	}

	/// ditto
	alias getLessThan = lowerBound;

	/**
	  * Retrieve everything in the map with a key greater than the given key.
	  *
	  * This retrieves only values that are strictly greater than the input, not greater than or equal
	  * to.
	  *
	  * The return value is a range of Elem structs, exposing `key` and `value` properties.
	  *
	  * The name is in keeping with Phobos's std.container.rbtree.
	  */
	auto upperBound(Key key) {
		auto elem = Elem(key, Value.init);
		return tree.upperBound(elem);
	}

	/// ditto
	alias getGreaterThan = upperBound;
}
