
string fun(string x, string y, string z = "Z", string w = "W")
{
	return x ~ y ~ z ~ w;
}

static assert(fun(   "x",    "y") == "xyZW");
static assert(fun(   "x",    "y", "z", "w") == "xyzw");
static assert(fun(x: "x", y: "y", z: "z", w: "w") == "xyzw");
static assert(fun(w: "w", z: "z", y: "y", x: "x") == "xyzw");
static assert(fun(y: "y",    "z", x: "x") == "xyzW");
static assert(fun(   "x",    "y", w: "w") == "xyZw");

// UFCS
static assert("x".fun("y", w: "w") == "xyZw");

// tuples
alias AliasSeq(T...) = T;

static assert("x".fun(x: AliasSeq!(), "y", w: "w") == "xyZw");
static assert(AliasSeq!("x", "y").fun(w: "w", z: AliasSeq!()) == "xyZw");
static assert(fun(y: AliasSeq!("y", "z", "w"), x: "x") == "xyzw");

// `new` expressions
class C
{
	int x, y;

	this(int x, int y)
	{
		this.x = x;
		this.y = y;
	}

	static C opCall(int x, int y) { return new C(x, y); }
}

struct S
{
	int x, y;
}

static assert(new C(y: 3, x: 2).x == 2);
static assert(    C(y: 3, x: 2).x == 2);
static assert(new S(y: 3, x: 2).x == 2);
static assert(    S(y: 3, x: 2).x == 2);

// opCall
struct Div
{
    static int opCall(int numer, int denom) { return numer / denom; }
}
static assert(Div(denom: 3, numer: 6) == 2);

struct Concat
{
	string s = "s";
    string opCall(string st0, string st1) { return s ~ st0 ~ st1; }
}

static assert(Concat.init("t0", "t1") == "st0t1");
