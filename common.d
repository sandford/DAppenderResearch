module common;

import std.array;
import core.stdc.string;
    
string fastJoin(string[] strings...)
{
    size_t length = 0;
    foreach (s; strings)
        length += s.length;
    auto result = new char[length];
    auto p = result.ptr;
    foreach (s; strings)
    {
        memcpy(p, s.ptr, s.length);
        p += s.length;
    }
    return cast(string)result;
}

string fastJoinArr(string[] strings)
{
    size_t length = 0;
    foreach (s; strings)
        length += s.length;
    auto result = new char[length];
    auto p = result.ptr;
    foreach (s; strings)
    {
        memcpy(p, s.ptr, s.length);
        p += s.length;
    }
    return cast(string)result;
}

string s1 = "aeou";
string s2 = "iueiue";
string s3 = "459ota";
string s4 = "5849otues";
string s5 = "poucil";

// **************************************************************************************
import std.range;

string testAppender(A)(int N) { 
    A app;
    foreach(_n; 0..N) {
        put(app, `<table id="group-index" class="forum-table group-wrapper viewmode-`);
        put(app, s1);
        put(app, `">`);
        put(app, `<tr class="group-index-header"><th><div>`);
        put(app, s2);
        put(app, `</div></th></tr>`);
        put(app, s3);
        put(app, `<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
        put(app, s4);
        put(app, `</table></div></td></tr>`);
        put(app, s5);
        put(app, `</table>`);
    }
    static if(is(A == string)) {
        return app;
    } else {
        return app.data;
    }
}

enum mixResultPutMulti = q{
    result.put(
        `APPENDER2 ="group-index" class="forum-table group-wrapper viewmode-`, s1, `">`
        `<tr class="group-index-header"><th><div>`, s2, `</div></th></tr>`, s3,
        `<tr><td class="group-threads-cell"><div class="group-threads"><table>`,
        s4, 
        `</table></div></td></tr>`,
        s5,
        `</table>`
    );
};

