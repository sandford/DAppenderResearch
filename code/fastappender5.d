module code.fastappender5;

import core.memory;
import core.stdc.string;

debug import std.stdio;

/// Optimized copying appender, no chaining, uses array vararg
import std.traits;

enum useASM = true;

/// Slice storer
struct FastAppender5(A : _T[], _T)
{
    alias Unqual!_T T;	
    static assert(T.sizeof == 1, "TODO");

    private enum MIN_SIZE  = 4096;
    private enum PAGE_SIZE = 4096;

    private T* cursor, start, end;

    void put(const(T)[][] items...)
    {
        auto cursorEnd = cursor;
        foreach (item; items)
            cursorEnd += item.length;

        if (cursorEnd > end)
        {
            auto len = cursorEnd - cursor;
            reserve(len);
            cursorEnd = cursor + len;
        }
        auto cursor = this.cursor;
        this.cursor = cursorEnd;

        foreach (item; items)
        {
            static if (useASM)
            {
                auto itemPtr = item.ptr;
                auto itemLen = item.length;
                asm
                {
                    mov ESI, itemPtr;
                    mov EDI, cursor;
                    mov ECX, itemLen;

                    rep;
                    movsb;
                    /*
                    add ECX, 3;
                    shr ECX, 2;
                    rep;
                    movsd;
                    */
                }
            }
            else
                cursor[0..item.length] = item;
            cursor += item.length;
        }
    }

    void reserve(size_t len)
    {
        auto size = cursor-start;
        auto newSize = size + len;
        auto capacity = end-start;

        if (start)
        {
            debug writeln("extend ", newSize, " .. ", newSize * 2);
            auto extended = GC.extend(start, newSize, newSize * 2);
            debug writeln("  --> ", extended);
            if (extended)
            {
                end = start + extended;
                return;
            }
        }

        auto newCapacity = nextCapacity(newSize);
        //auto newStart = (new T[newCapacity]).ptr;

        debug writeln("qalloc ", newCapacity);
        auto bi = GC.qalloc(newCapacity * T.sizeof, (typeid(T[]).next.flags & 1) ? 0 : GC.BlkAttr.NO_SCAN);
        debug writeln("  ==> ", bi.size);
        auto newStart = cast(T*)bi.base;
        newCapacity = bi.size;

        newStart[0..size] = start[0..size]; // TODO: memcpy?
        start = newStart;
        cursor = start + size;
        end = start + newCapacity;
    }

    // Round up to the next power of two, but after PAGE_SIZE only add PAGE_SIZE.
    private static size_t nextCapacity(size_t size)
    {
        if (size < MIN_SIZE)
            return MIN_SIZE;

        size--;
        auto sub = size;
        sub |= sub >>  1;
        sub |= sub >>  2;
        sub |= sub >>  4;
        sub |= sub >>  8;
        sub |= sub >> 16;
        static if (size_t.sizeof > 4)
            sub |= sub >> 32;

        return (size | (sub & (PAGE_SIZE-1))) + 1;
    }

    unittest
    {
        assert(nextCapacity(  PAGE_SIZE-1) ==   PAGE_SIZE);
        assert(nextCapacity(  PAGE_SIZE  ) ==   PAGE_SIZE);
        assert(nextCapacity(  PAGE_SIZE+1) == 2*PAGE_SIZE);
        assert(nextCapacity(2*PAGE_SIZE  ) == 2*PAGE_SIZE);
        assert(nextCapacity(2*PAGE_SIZE+1) == 3*PAGE_SIZE);
    }

    A data()
    {
        return cast(A) start[0..cursor-start];
    }
}
