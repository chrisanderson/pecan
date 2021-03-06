package test;

import pecan.Co.co;
import pecan.Co.coDebug;
import utest.Async;

class TestCoroutine extends Test {
  /**
    Proper call order:
    - 0 - called after coroutine is created but before coroutine is ticked
    - 1 - first tick in coroutine
    - 2 - coroutine was suspended, call after the tick
    - 3 - coroutine woken up with a call
    - 4 - coroutine woken up with a timer
  **/
  function testOrder(async:Async) {
    var calls = [];
    var c = co({
      calls.push(1);
      if (true) {
        if (false) {
          calls.push(-1);
        } else {
          suspend();
        }
      } else {
        calls.push(-1);
      }
      calls.push(3);
      haxe.Timer.delay(self.wakeup, 1);
      suspend();
      calls.push(4);
      aeq(calls, [0, 1, 2, 3, 4]);
      async.done();
    }).runSuspended();
    calls.push(0);
    c.tick();
    calls.push(2);
    c.wakeup();
  }

  /**
    Variable scoping.
  **/
  function testVars() {
    var a = 1;
    var b = 2;
    co({
      // external variable
      b = 3;

      // `a` here should refer to the `a` outside
      eq(a, 1);

      var a = 3;
      var b = 4;
      eq(a, 3);
      eq(b, 4);

      // some ops
      eq(a + b, 7);
      eq(a - b, -1);
      eq(a * b, 12);
      eq(++a, 4);
      eq(a++, 4);
      eq(a, 5);
      t(a == b + 1);
      eq(a - 1 == b ? 1 : 2, 1);

      // `a` here should shadow the first `a`
      var a = 5;
      eq(a, 5);
      eq(b, 4);

      {
        // `a` here shadows the previous `a` but only inside this block
        var a = 7;
        eq(a, 7);
      }

      // back to the previous `a`
      eq(a, 5);

      // switch cases are also scopes
      switch (a) {
        case 3:
          var a = 3;
          assert();
        case 5:
          eq(a, 5);
          var a = 6;
          eq(a, 6);
        case _:
          assert();
      }

      // back to the previous `a`
      eq(a, 5);

      // different type
      var a = "foo";
      eq(a, "foo");
    }).run();
    eq(b, 3);
  }

  /**
    Coroutine states and state errors.
  **/
  function testStates() {
    var c = co({
      suspend();
      var a = accept();
      yield(0);
    }, (_ : Int), (_ : Int)).runSuspended();
    eq(c.state, Ready);
    exc(() -> c.give(0));
    exc(() -> c.take());
    c.tick();
    eq(c.state, Suspended);
    exc(() -> c.give(0));
    exc(() -> c.take());
    c.tick();
    eq(c.state, Suspended);
    c.wakeup();
    t(c.state.match(Accepting));
    c.tick();
    t(c.state.match(Accepting));
    exc(() -> c.take());
    exc(() -> c.wakeup());
    c.give(0);
    t(c.state.match(Yielding));
    exc(() -> c.give(0));
    exc(() -> c.wakeup());
    c.take();
    eq(c.state, Terminated);
    exc(() -> c.wakeup());
    exc(() -> c.give(0));
    exc(() -> c.take());

    var c = co({
      terminate();
      assert("fail");
    }, (_ : Int)).runSuspended();
    c.tick();
    eq(c.state, Terminated);
    c.tick();
    eq(c.state, Terminated);
    exc(() -> c.wakeup());
    exc(() -> c.give(0));
    exc(() -> c.take());
  }

  /**
    Data input and output.
  **/
  function testIO() {
    // input only
    var c = co({
      var a = "foo";
      eq(a, "foo");
      a = accept();
      eq(a, "bar");
      if (true) {
        var a = accept();
        eq(a, "hello");
      }
      eq(a, "bar");
    }, (_ : String)).run();
    c.give("bar");
    c.give("hello");

    // output only
    var c = co({
      yield("foo");
      var a = "bar";
      yield(a);
    }, null, (_ : String)).run();
    eq(c.take(), "foo");
    eq(c.take(), "bar");

    // both input and output
    var c = co({
      yield(0);
      var a = accept();
      eq(a, 1);
      yield(a + 1);
    }, (_ : Int), (_ : Int)).run();
    eq(c.take(), 0);
    c.give(1);
    eq(c.take(), 2);

    // combined assignment operator
    var c = co({
      var a = 3;
      a += accept();
      eq(a, 4);
    }, (_ : Int)).run();
    c.give(1);
  }

  /**
    Various control flow blocks.
  **/
  function testSyntax() {
    // if/else blocks
    var c = co({
      if (true) {
        suspend();
        if (false) {
          eq(1, 0);
        } else {
          suspend();
          if (true) {
            suspend();
            eq(1, 1);
          }
        }
      } else {
        suspend();
        eq(1, 0);
      }
    }).run();
    c.wakeup();
    c.wakeup();
    c.wakeup();

    // loops
    var c = co({
      var counter = 0;
      while (true) yield(counter++);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    t(c.state.match(Yielding));

    var c = co({
      while (false) yield(0);
    }, null, (_ : Int)).run();
    eq(c.state, Terminated);

    var c = co({
      do yield(0) while (false);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.state, Terminated);

    var c = co({
      var counter = 0;
      while (counter < 3) yield(counter++);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      var counter = 0;
      do yield(counter++) while (counter < 3);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      var counter = 0;
      do {
        // yield first in block
        yield(counter++);
        1 + 1;
      } while (counter < 3);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      var counter = 0;
      do {
        // yield last in block
        1 + 1;
        yield(counter++);
      } while (counter < 3);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      for (i in 0...3) {
        yield(i);
      }
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    var c = co({
      for (i in [0, 1, 2]) yield(i);
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    // without a block
    var c = co(for (i in [0, 1, 2]) yield(i), null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.take(), 2);
    eq(c.state, Terminated);

    /*
    var c = co({ // TODO: Instance prototype not found: haxe.iterators.MapKeyValueIterator ?
      // order is not defined in maps
      for (k => v in [0 => 0, 1 => 1, 2 => 2]) {
        eq(k, v);
      }
    }).run();
    eq(c.state, Terminated);
    */
  }

  /**
    String interpolation.
  **/
  function testStringInterpolation() {
    var a = 1;
    co({
      eq('$a', "1");
      eq('${a + 1}', "2");
      var a = 3;
      eq('$a', "3");
    }).run();
  }

  /**
    Argument passing.
  **/
  function testArguments() {
    co((a:Int) -> {
      eq(a, 1);
      a++;
      eq(a, 2);
    }).run(1);
    var c = co((a:String, b:Float) -> {
      eq(a, "foo");
      eq(b, 1.0);
      suspend();
      eq(a, "foo");
      eq(b, 1.0);
    }).run("foo", 1.0);
    c.wakeup();
    eq(c.state, Terminated);

    // optional and default
    co((?a:String) -> {
      eq(a, null);
    }).run();

    co((?a:String = "foo", ?b:Int = 2) -> {
      eq(a, "foo");
      eq(b, 2);
    }).run();
    co((?a:String = "foo", ?b:Int = 2) -> {
      eq(a, "bar");
      eq(b, 4);
    }).run("bar", 4);
    co((?a:String = "foo", ?b:Int = 2) -> {
      eq(a, "bar");
      eq(b, 2);
    }).run("bar");
    co((?a:String = "foo", ?b:Int = 2) -> {
      eq(a, "foo");
      eq(b, 4);
    }).run(4);
  }

  function testAccept() {
    var c = co({
      var a = accept();
      eq(a, 0);
    }, (_ : Int)).run();
    c.give(0);
    eq(c.state, Terminated);

    var c = co({
      var a = accept() + accept();
      eq(a, 3);
    }, (_ : Int)).run();
    c.give(1);
    c.give(2);
    eq(c.state, Terminated);

    var c = co({
      if (accept()) {
        eq(1, 1);
      } else {
        eq(0, 1);
      }
    }, (_ : Bool)).run();
    c.give(true);
    eq(c.state, Terminated);

    var c = co({
      var a = accept() ? 1 : 0;
      eq(1, 1);
    }, (_ : Bool)).run();
    c.give(true);
    eq(c.state, Terminated);

    var c = co({
      var a = true ? accept() : accept();
      eq(1, 1);
    }, (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);

    var c = co({
      yield(accept() + 1);
    }, (_ : Int), (_ : Int)).run();
    c.give(0);
    eq(c.take(), 1);
    eq(c.state, Terminated);
  }

  /**
    Test each ExprDef constructor with suspending calls (where possible).
  **/
  function testExpressions() {
    // EConst
    co(eq(1, 1)).run();

    // EArray
    var c = co(eq([0, 1, 0][accept()], 1), (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);
    var c = co(eq(accept()[1], 1), (_ : Array<Int>)).run();
    c.give([0, 1, 0]);
    eq(c.state, Terminated);
    var c = co({
      var x = [];
      x[0] = accept();
      eq(x[0], 1);
    }, (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);

    // EBinop
    var c = co(eq(accept() + 2, 3), (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);
    var c = co(eq(2 + accept(), 3), (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);

    // EBinop short-circuit
    // TODO: implement in CFG
    /*
    var c = coDebug(eq(accept() && accept(), false), (_ : Bool)).run();
    c.give(false);
    c.give(false);
    eq(c.state, Terminated);
    var c = co(eq(accept() || accept(), true), (_ : Bool)).run();
    c.give(true);
    eq(c.state, Terminated);
    */

    // EField
    var c = co(eq(accept().x, 1), (_ : {x:Int})).run();
    c.give({x: 1});
    eq(c.state, Terminated);

    // EParenthesis
    var c = co(eq((accept()), 1), (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);

    // EObjectDecl
    var c = co(eq({x: accept()}.x, 1), (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);

    // EArrayDecl
    var c = co(eq([0, accept(), 0][1], 1), (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);

    // ECall
    var called = false;
    var func = x -> { called = true; eq(x, 1); };
    var c = co(accept()(1), (_ : Int -> Void)).run();
    c.give(func);
    eq(called, true);
    eq(c.state, Terminated);
    called = false;
    var c = co(func(accept()), (_ : Int)).run();
    c.give(1);
    eq(called, true);
    eq(c.state, Terminated);

    // ENew
    var c = co(yield(new DummyObject(accept())), (_ : Int), (_ : test.TestCoroutine.DummyObject)).run();
    c.give(1);
    eq(c.take().x, 1);
    eq(c.state, Terminated);

    // EUnop
    var c = co(eq(!accept(), true), (_ : Bool)).run();
    c.give(false);
    eq(c.state, Terminated);

    // EVars
    var c = co({
      var x = accept();
      eq(x, true);
    }, (_ : Bool)).run();
    c.give(true);
    eq(c.state, Terminated);

    // EBlock
    var reached = false;
    var c = co(eq({
      eq(1, 1);
      reached = true;
      accept();
    }, 1), (_ : Int)).run();
    c.give(1);
    eq(reached, true);
    eq(c.state, Terminated);

    // EFor
    var c = co({
      for (x in accept()) eq(x, 42);
    }, (_ : Array<Int>)).run();
    c.give([42]);
    eq(c.state, Terminated);

    // EIf
    var c = co(eq(if (accept()) {
      1;
    } else {
      0;
    }, 1), (_ : Bool)).run();
    c.give(true);
    eq(c.state, Terminated);

    // EWhile
    var c = co({
      var done = false;
      while (accept()) {
        eq(done, false);
        done = true;
      }
    }, (_ : Bool)).run();
    c.give(true);
    c.give(false);
    eq(c.state, Terminated);

    // ESwitch
    var c = co({
      switch (accept()) {
        case 5 if (accept() > 0):
          assert();
        case 5:
          eq(accept(), 10);
        case _:
          assert();
      }
    }, (_ : Int)).run();
    c.give(5);
    c.give(-1);
    c.give(10);
    eq(c.state, Terminated);

    // ETry
    var c = co({
      try {
        try {
          throw accept() + 1;
          assert();
        } catch (e:String) {
          assert();
        } catch (e:Int) {
          throw accept() + e;
        } catch (e:Float) {
          assert();
        }
        assert();
      } catch (e:Int) {
        eq(e, 6);
      }
    }, (_ : Int)).run();
    c.give(2);
    c.give(3);
    eq(c.state, Terminated);

    // EBreak
    var c = co({
      for (i in 0...3) {
        if (i > 1) break;
        yield(i);
      }
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.state, Terminated);

    // EContinue
    var c = co({
      for (i in 0...3) {
        if (i < 2) {
          yield(i);
          continue;
        }
        break;
        assert();
      }
    }, null, (_ : Int)).run();
    eq(c.take(), 0);
    eq(c.take(), 1);
    eq(c.state, Terminated);

    // ETernary
    var c = co(eq(accept() ? 1 : 0, 1), (_ : Bool)).run();
    c.give(true);
    eq(c.state, Terminated);

    // EMeta
    var c = co(eq(@foo accept(), 1), (_ : Int)).run();
    c.give(1);
    eq(c.state, Terminated);
  }

  /**
    Test array and map comprehension.
  **/
  function testComprehension() {
    var c = co({
      var a = [ for (i in 0...3) accept() ];
      aeq(a, [2, 1, 0]);
    }, (_ : Int)).run();
    c.give(2);
    c.give(1);
    c.give(0);
    eq(c.state, Terminated);

    var c = co({
      var i = 0;
      var a = [ while (i < 3) { i++; accept(); } ];
      aeq(a, [2, 1, 0]);
    }, (_ : Int)).run();
    c.give(2);
    c.give(1);
    c.give(0);
    eq(c.state, Terminated);

    var c = co({
      var i = 0;
      var a = [ while (i++ < 3) accept() ];
      aeq(a, [2, 1, 0]);
    }, (_ : Int)).run();
    c.give(2);
    c.give(1);
    c.give(0);
    eq(c.state, Terminated);

    var c = co({
      var a = [ for (i in 0...3) i => accept() ];
      eq(a[0], "a");
      eq(a[1], "b");
      eq(a[2], "c");
    }, (_ : String)).run();
    c.give("a");
    c.give("b");
    c.give("c");
    eq(c.state, Terminated);

    var c = co({
      var i = 0;
      var a = [ while (i++ < 3) i => accept() ];
      eq(a[1], "a");
      eq(a[2], "b");
      eq(a[3], "c");
    }, (_ : String)).run();
    c.give("a");
    c.give("b");
    c.give("c");
    eq(c.state, Terminated);

    var c = co({
      var i = 0;
      var a = [ for (i in 0...2) for (j in 0...2) i * 2 + j => accept() ];
      eq(a[0], "a");
      eq(a[1], "b");
      eq(a[2], "c");
      eq(a[3], "d");
    }, (_ : String)).run();
    c.give("a");
    c.give("b");
    c.give("c");
    c.give("d");
    eq(c.state, Terminated);
  }

  /**
    Test labels and goto.
  **/
  function testLabels() {
    var c = co({
      label("giveA");
      while (true)
        yield("A");
      label("giveB");
      while (true)
        yield("B");
    }, null, (_ : String)).run();
    eq(c.take(), "A");
    eq(c.take(), "A");
    c.goto("giveB");
    eq(c.take(), "B");
    eq(c.take(), "B");
    c.goto("giveA");
    eq(c.take(), "A");
    c.goto("giveB");
    c.goto("giveA");
    eq(c.take(), "A");
    exc(() -> c.goto("invalid"));
  }
}

class DummyObject {
  public final x:Int;

  public function new(x:Int) {
    this.x = x;
  }
}
