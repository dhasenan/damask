module dmud.container;

/**
	* A queue implemented as a circular buffer.
  *
	* Queues have a fixed size (compile time constant, default 50). You cannot push more than that
	* number of elements into the queue; further pushes are rejected.
	*/
struct Queue(T, int size = 50) {
	T[size] array;
	int first = 0;
	int count = 0;

	bool push(T value) {
		if (full) return false;
		auto i = (first + count) % size;
		array[i] = value;
		count++;
		return true;
	}

	bool pop(out T value) {
		if (empty) return false;
		count--;
		value = array[first];
		first++;
		first %= size;
		return true;
	}

	bool empty() {
		return count == 0;
	}

	bool full() {
		return count >= size;
	}
}

unittest {
	Queue!(int, 5) a;
	int t;
	assert(a.empty);
	assert(!a.pop(t));
	a.push(10);
	assert(a.pop(t));
	assert(t == 10);
	assert(a.empty);


	a.push(5);
	a.push(6);
	a.push(7);
	a.push(8);
	assert(a.push(9));
	assert(!a.push(10));
	assert(a.pop(t));
	assert(t == 5);
	assert(a.pop(t));
	assert(t == 6);
	assert(a.pop(t));
	assert(t == 7);
	assert(a.pop(t));
	assert(t == 8);
	assert(a.pop(t));
	assert(t == 9);
	assert(!a.pop(t));
}
