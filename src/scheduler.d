module dmud.scheduler;

import dmud.eventqueue;
import core.thread;
import std.concurrency;

/**
  * A fiber scheduler specialized to our needs.
  *
  * We have a simulation that needs to proceed in fixed timesteps, and that covers most of our code.
  * We use an event queue so we can (hopefully!) schedule occasional tasks efficiently.
  * We want to alert on anything that takes too long to execute.
  * We also want some items that are automatically scheduled very frequently.
  * This all requires a custom scheduler.
  */
class MudScheduler : Scheduler {
	private EventQueue!Fiber _queue;
	private SimClock _clock;
	private SysTime _nextTick;

	this(SimClock clock) {
		_clock = clock;
		_queue = new EventQueue!Fiber();
	}

	this(EventQueue!Fiber queue, SimClock clock) {
		_queue = queue;
		_clock = clock;
	}

	EventQueue!Fiber queue() { return _queue; }

	/**
	  * Create a system fiber.
	  *
	  * We cycle through system fibers at least once per tick and whenever we are not busy with
	  * simulation stuff. So if the simulation completes its tick in half the time we allotted, we
	  * spend the rest of the time running through 
	  */
	Fiber system(void delegate() op) {
		Fiber f = create(op);
		_systemFibers ~= f;
		return f;
	}

	/**
	  * Create a client fiber.
	  *
	  * Client fibers get scheduled every tick by default, but they can use triggers or sleep and
	  * thereby not be scheduled for a while. They will never be scheduled twice in one tick.
	  */
	Fiber client(void delegate() op) {
		Fiber f = create(op);
		_clientFibers ~= f;
		return f;
	}

	// Most of this implementation was lifted from std.concurrency.
	// That code is under the Boost license v1.0 and belongs to the D developers.

	void start(void delegate() op) {
		_nextTick = Clock.currTime + _clock.tickDuration;
		create(op);
		dispatch();
	}

	void spawn(void delegate() op) nothrow {
		create(op);
		yield();
	}

	void yield() nothrow {
		auto fiber = cast(MudFiber) Fiber.getThis;
		assert(fiber, "Unknown type of fiber being rescheduled! Are you mixing multiple schedulers?");
		if (fiber.isClient) {
			_queue.
		}

		if (Fiber.getThis())
			Fiber.yield();
	}

	@property ref ThreadInfo thisInfo() nothrow {
		auto f = cast(MudFiber) Fiber.getThis();
		if (f !is null) return f.info;
		return ThreadInfo.thisInfo;
	}

	Condition newCondition(Mutex m) nothrow {
		return new FiberCondition(m);
	}

	private static class MudFiber : Fiber {
		ThreadInfo info;

		this(void delegate() op) nothrow {
			super(op);
		}
	}

	private class FiberCondition : Condition {
		this(Mutex m) nothrow {
			super(m);
			notified = false;
		}

		override void wait() nothrow {
			scope(exit) notified = false;

			while (!notified) {
				switchContext();
			}
		}

		override bool wait(Duration period) nothrow {
			import core.time : MonoTime;
			scope(exit) notified = false;

			for (auto limit = MonoTime.currTime + period;
					!notified && !period.isNegative;
					period = limit - MonoTime.currTime) {
				yield();
			}
			return notified;
		}

		override void notify() nothrow {
			notified = true;
			switchContext();
		}

		override void notifyAll() nothrow {
			notified = true;
			switchContext();
		}

		private final void switchContext() nothrow {
			mutex_nothrow.unlock_nothrow();
			scope(exit) mutex_nothrow.lock_nothrow();
			yield();
		}

		private bool notified;
	}

	private enum State {
		InitSystem,
		Client,
		Queue,
		FillSystem
	}
	private State state = State.InitSystem;
	private size_t _pos = 0;
	private final void dispatch() {
		while (_systemFibers.length || _clientFibers.length || _queue.length) {
			while (state == State.InitSystem) {
				if (_pos >= _systemFibers.length) {
					_pos = 0;
					state = State.Client;
					break;
				}
				auto fiber = _systemFibers[_pos];
				_pos++;
				tryDispatch(fiber);
			}
			while (state == State.Client) {
				if (_pos >= _clientFibers.length) {
					_pos = 0;
					state = State.Queue;
					break;
				}
				auto fiber = _clientFibers[_pos];
				_pos++;
				tryDispatch(fiber);
			}
			while (state == State.Queue) {
				auto elem = _queue.front;
				if (elem.key != _clock.now) {
					state = State.FillSystem;
					break;
				}
				// TODO: ensure that a fiber that went into the queue but needs to go into _clientFibers
				// does so.
				// For instance, I have a fiber that goes:
				// ---
				// sleepUntil(dawn);
				// say("Hi!");
				// yield();
				// say("That was a good nap.");
				// ---
				// I remove it from _clientFibers when it says sleepUntil. Then I need to add it back when
				// it yields next, but only if it doesn't yield into the queue.
				auto fiber = _queue.pop();
				tryDispatch(elem.key);
			}
			while ()
		}
		while (m_fibers.length > 0) {
			auto t = m_fibers[m_pos].call(Fiber.Rethrow.no);
			if (t !is null && !(cast(OwnerTerminated) t)) {
				throw t;
			}
			if (m_fibers[m_pos].state == Fiber.State.TERM) {
				if (m_pos >= (m_fibers = remove(m_fibers, m_pos)).length) {
					m_pos = 0;
				}
			} else if (m_pos++ >= m_fibers.length - 1) {
				m_pos = 0;
			}
		}
	}

	private final Fiber create(void delegate() op) nothrow {
		void wrap() {
			scope(exit) {
				thisInfo.cleanup();
			}
			op();
		}
		auto fiber = new MudFiber(&wrap);
		m_fibers ~= fiber;
		return fiber;
	}


	private:
	Fiber[] m_fibers;
	size_t  m_pos;
}
