module code.fastappender3;

import core.memory;
import core.stdc.string;
import std.traits;

/// Slice storer
struct FastAppender3(A : _T[], _T)
{
    alias Unqual!_T T;
    static assert(T.sizeof == 1, "TODO");

private:
    enum PAGE_SIZE = 4096;

    enum INDEX_NODE_SIZE = (PAGE_SIZE*64 / size_t.sizeof) - 2;

    alias const(T)[] Item;

    struct IndexNode
    {
        Item[INDEX_NODE_SIZE] items;
        Item* end;
        IndexNode* next;

        @property Item[] liveItems()
        {
            return items[0..end - items.ptr];
        }
    }
    IndexNode* head, tail;

    Item* indexCursor, indexEnd;

    void extendIndex()
    {
        //auto newNode = new IndexNode;
        auto newNode = cast(IndexNode*)GC.malloc(IndexNode.sizeof, 0);
        newNode.next = null;

        if (!tail)
            head = tail = newNode;
        else
        {
            tail.end = indexCursor;
            tail.next = newNode;
            tail = newNode;
        }

        indexCursor = newNode.items.ptr;
        indexEnd = indexCursor + INDEX_NODE_SIZE;
    }

    void consolidate()
    {
        if (tail)
            tail.end = indexCursor;

        size_t length = 0;
        for (auto n = head; n; n = n.next)
            foreach (item; n.liveItems)
                length += item.length;

        auto s = new T[length];
        auto p = s.ptr;

        for (auto n = head; n; n = n.next)
            foreach (item; n.liveItems)
            {
                p[0..item.length] = item;
                p += item.length;
            }

        head = tail = null;
        extendIndex();
        *indexCursor++ = s;
    }

public:
    void put(U...)(U items)
    {
        static assert(items.length < INDEX_NODE_SIZE, "Too many items!");

        auto indexCursorL = indexCursor; // local copy
        auto indexPostCursor = indexCursorL + items.length;
        if (indexPostCursor > indexEnd)
        {
            extendIndex();
            indexCursorL = indexCursor;
            indexPostCursor = indexCursorL + items.length;
        }
        indexCursor = indexPostCursor;

        foreach (item; items)
            static if (is(typeof(item[0]) == immutable(T)))
                *indexCursorL++ = item;
            else
                static assert(0, "Can't put " ~ typeof(item).stringof);
    }

    A data()
    {
        consolidate();
        return cast(A) head.items[0];
    }


}
