import std.stdio;
import std.datetime;
import std.random;
import std.range;
import std.algorithm;
import std.array;
import core.memory;

import common;
import code.appender2;
import code.fastappender;
import code.fastappender2;
import code.fastappender3;
import code.fastappender4;
import code.fastappender5;
import code.fastappender6;
import code.fastappender7;
import code.fastappender8;
import core.appender3;


real[] bench(int N, int M, string delegate() methods[]...) {
    StopWatch sw;
    auto rnd      = Random(unpredictableSeed);
    auto times    = new real[methods.length];
         times[]  = int.max;
    foreach(_m;0..M) {
        foreach (ref i; randomCover(iota(0,methods.length), rnd)) {
            sw.start;
            foreach (_n; 0..N) {
                methods[i]();
            }
            sw.stop;
            times[i] = min(times[i], sw.peek.usecs);
            sw.reset;
        }
    }

    return times;
}

// For Variant
//S s;
//writeln( s.xyz = 5 );
struct S
{
    template opDispatch(string name)
    {
        int opDispatch(A...)(A args)
        {
          static if (args.length)
            return args[0];
          else
            return 0;
        }
    }
}
// Ref tuples
//foreach(ref element; s.tupleof)  // OK
//    element = 2;




void main() {
    try {
        //auto check = new ubyte[4096-512]; 4079  17 bytes?
        auto L = 10;

        auto times = bench(1_000, 10, 
                           // testAppender!string(L),
                           testAppender!(Appender!string)(L),
                           //testAppender!(Appender2!string)(L),
                           //testAppender!(FastAppender!string)(L),
                           testAppender!(FastAppender2!string)(L),//fast
                           //testAppender!(FastAppender3!string)(L),
                           //testAppender!(FastAppender4!string)(L),
                           //testAppender!(FastAppender5!string)(L),
                           //testAppender!(FastAppender6!string)(L),
                           //testAppender!(FastAppender7!string)(L),
                           testAppender!(FastAppender8!string)(L),// 2nd fast
                           //testAppender!(Appender3_full!string)(L), // original reference
                           //testAppender!(Appender3_old!string)(L),  // reference
                           testAppender!(Appender3_wip!string)(L),  // Work in progress 
                           );
        auto best = reduce!min(times);

        foreach(i, time; times) {
            writeln(i,"\t",time, time==best?" <-------":"");
        }
   
    } catch (Throwable o) {
        writeln(o); readln;
    }
    writeln("Done. Press Enter."); readln;
}


unittest
{
    struct A {}
    static assert(!isInputRange!(A));
    struct B
    {
        void put(int) {}
    }
    B b;
    put(b, 5);
}

unittest
{
    int[] a = [1, 2, 3], b = [10, 20];
    auto c = a;
    put(a, b);
    assert(c == [10, 20, 3]);
    assert(a == [3]);
}

unittest
{
    int[] a = new int[10];
    int b;
    static assert(isInputRange!(typeof(a)));
    put(a, b);
}

unittest
{
    void myprint(in char[] s) { }
    auto r = &myprint;
    put(r, 'a');
}

unittest
{
    int[] a = new int[10];
    static assert(!__traits(compiles, put(a, 1.0L)));
    static assert( __traits(compiles, put(a, 1)));
    /*
     * a[0] = 65;       // OK
     * a[0] = 'A';      // OK
     * a[0] = "ABC"[0]; // OK
     * put(a, "ABC");   // OK
     */
    static assert( __traits(compiles, put(a, "ABC")));
}

unittest
{
    char[] a = new char[10];
    static assert(!__traits(compiles, put(a, 1.0L)));
    static assert(!__traits(compiles, put(a, 1)));
    // char[] is NOT output range.
    static assert( __traits(compiles, put(a, 'a')));///////////////////////////////////////////
    static assert( __traits(compiles, put(a, "ABC")));/////////////////////////////////////
}

// is output range
unittest
{
    void myprint(in char[] s) { writeln('[', s, ']'); }
    static assert(isOutputRange!(typeof(&myprint), char));

    auto app = appender!string();
    string s;
    static assert( isOutputRange!(Appender!string, string));
    static assert( isOutputRange!(Appender!string*, string));
    static assert(!isOutputRange!(Appender!string, int));
    static assert( isOutputRange!(char[], char)); /////////////////////////////
    static assert( isOutputRange!(wchar[], wchar));////////////////////////////////
    static assert( isOutputRange!(dchar[], char));
    static assert( isOutputRange!(dchar[], wchar));
    static assert( isOutputRange!(dchar[], dchar));
}
