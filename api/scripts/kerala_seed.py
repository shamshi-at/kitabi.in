"""Curated seed data — major Malayalam / Kerala authors, their publishers, and a
few of their major works. Names + pen names + works are hand-curated; image and
logo URLs are filled in from `kerala_seed_images.py` (fetched from Wikimedia) at
load time, so this file stays free of brittle URLs.

Loaded by `scripts/seed_catalog.py` (idempotent — safe to re-run)."""

# Publishers of Malayalam literature. `logo_url` is merged in from the images
# file when available.
PUBLISHERS: list[dict] = [
    {"name": "DC Books"},
    {"name": "Mathrubhumi Books"},
    {"name": "Current Books"},
    {"name": "National Book Stall"},  # SPCS / Sahitya Pravarthaka Co-operative Society
    {"name": "Green Books"},
    {"name": "Poorna Publications"},
    {"name": "Chintha Publishers"},
    {"name": "Lipi Publications"},
    {"name": "Kairali Books"},
    {"name": "Manorama Books"},
]

# name = the commonly-known name; pen_name = a notable writing/alternate name.
# publisher = a plausible primary publisher for their works' seed editions.
AUTHORS: list[dict] = [
    {
        "name": "Thakazhi Sivasankara Pillai",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Chemmeen", "year": 1956},
            {"title": "Kayar", "year": 1978},
            {"title": "Randidangazhi", "year": 1948},
            {"title": "Enippadikal", "year": 1964},
        ],
    },
    {
        "name": "Vaikom Muhammad Basheer",
        "pen_name": "Beypore Sultan",
        "publisher": "DC Books",
        "works": [
            {"title": "Balyakalasakhi", "year": 1944},
            {"title": "Pathummayude Aadu", "year": 1959},
            {"title": "Mathilukal", "year": 1965},
            {"title": "Ntuppuppakkoranendarnnu", "year": 1951},
        ],
    },
    {
        "name": "O.V. Vijayan",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Khasakkinte Itihasam", "year": 1969},
            {"title": "Dharmapuranam", "year": 1985},
            {"title": "Gurusagaram", "year": 1987},
        ],
    },
    {
        "name": "M.T. Vasudevan Nair",
        "pen_name": "MT",
        "publisher": "Current Books",
        "works": [
            {"title": "Naalukettu", "year": 1958},
            {"title": "Randamoozham", "year": 1984},
            {"title": "Kaalam", "year": 1969},
            {"title": "Asuravithu", "year": 1962},
        ],
    },
    {
        "name": "Kamala Das",
        "pen_name": "Madhavikutty",
        "publisher": "DC Books",
        "works": [
            {"title": "Ente Katha", "year": 1973},
            {"title": "Neermathalam Pootha Kalam", "year": 1993},
            {"title": "Pakshiyude Manam", "year": 1964},
        ],
    },
    {
        "name": "S.K. Pottekkatt",
        "pen_name": None,
        "publisher": "Current Books",
        "works": [
            {"title": "Oru Desathinte Katha", "year": 1971},
            {"title": "Vishakanyaka", "year": 1948},
        ],
    },
    {
        "name": "Lalithambika Antharjanam",
        "pen_name": None,
        "publisher": "Current Books",
        "works": [{"title": "Agnisakshi", "year": 1976}],
    },
    {
        "name": "P. Kesava Dev",
        "pen_name": None,
        "publisher": "National Book Stall",
        "works": [
            {"title": "Odayil Ninnu", "year": 1942},
            {"title": "Ayalkkar", "year": 1963},
        ],
    },
    {
        "name": "Uroob",
        "pen_name": "P.C. Kuttikrishnan",
        "publisher": "Current Books",
        "works": [
            {"title": "Ummachu", "year": 1954},
            {"title": "Sundarikalum Sundaranmarum", "year": 1958},
        ],
    },
    {
        "name": "M. Mukundan",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Mayyazhippuzhayude Theerangalil", "year": 1974},
            {"title": "Daivathinte Vikrithikal", "year": 1989},
            {"title": "Kesavante Vilapangal", "year": 2010},
        ],
    },
    {
        "name": "Anand",
        "pen_name": "P. Sachidanandan",
        "publisher": "DC Books",
        "works": [
            {"title": "Aalkoottam", "year": 1970},
            {"title": "Govardhante Yathrakal", "year": 1984},
            {"title": "Marana Certificate", "year": 1994},
        ],
    },
    {
        "name": "Punathil Kunjabdulla",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Smarakasilakal", "year": 1977},
            {"title": "Marunnu", "year": 2007},
        ],
    },
    {
        "name": "Malayattoor Ramakrishnan",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Verukal", "year": 1966},
            {"title": "Yakshi", "year": 1967},
        ],
    },
    {
        "name": "C.V. Raman Pillai",
        "pen_name": None,
        "publisher": "National Book Stall",
        "works": [
            {"title": "Marthandavarma", "year": 1891},
            {"title": "Dharmaraja", "year": 1913},
            {"title": "Ramarajabahadur", "year": 1918},
        ],
    },
    {
        "name": "Sara Joseph",
        "pen_name": None,
        "publisher": "Current Books",
        "works": [
            {"title": "Aalahayude Penmakkal", "year": 1999},
            {"title": "Mattathi", "year": 2003},
            {"title": "Othappu", "year": 2005},
        ],
    },
    {
        "name": "K.R. Meera",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Aarachar", "year": 2012},
            {"title": "Meerasadhu", "year": 2008},
        ],
    },
    {
        "name": "Benyamin",
        "pen_name": None,
        "publisher": "Green Books",
        "works": [
            {"title": "Aadujeevitham", "year": 2008},
            {"title": "Manja Veyil Maranangal", "year": 2011},
        ],
    },
    {
        "name": "Perumbadavam Sreedharan",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [{"title": "Oru Sankeerthanam Pole", "year": 1993}],
    },
    {
        "name": "T. Padmanabhan",
        "pen_name": None,
        "publisher": "Mathrubhumi Books",
        "works": [
            {"title": "Gauri", "year": 1993},
            {"title": "Makhan Singhinte Maranam", "year": 1959},
        ],
    },
    {
        "name": "Paul Zacharia",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Bhaskara Pattelarum Ente Jeevithavum", "year": 1993},
            {"title": "Salaam America", "year": 2001},
        ],
    },
    {
        "name": "N.S. Madhavan",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Lanthan Batheriyile Luthiniyakal", "year": 2003},
            {"title": "Hijra", "year": 2001},
        ],
    },
    {
        "name": "Subhash Chandran",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [{"title": "Manushyanu Oru Aamukham", "year": 2009}],
    },
    {
        "name": "Kovilan",
        "pen_name": None,
        "publisher": "Current Books",
        "works": [
            {"title": "Thattakam", "year": 1995},
            {"title": "A Minus B", "year": 1967},
        ],
    },
    {
        "name": "Kakkanadan",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Vasoori", "year": 1968},
            {"title": "Sakshi", "year": 1970},
        ],
    },
    {
        "name": "O. Chandu Menon",
        "pen_name": None,
        "publisher": "National Book Stall",
        "works": [{"title": "Indulekha", "year": 1889}],
    },
    {
        "name": "Kumaran Asan",
        "pen_name": None,
        "publisher": "National Book Stall",
        "works": [
            {"title": "Veena Poovu", "year": 1907},
            {"title": "Nalini", "year": 1911},
            {"title": "Chandalabhikshuki", "year": 1922},
            {"title": "Duravastha", "year": 1922},
        ],
    },
    {
        "name": "Vallathol Narayana Menon",
        "pen_name": None,
        "publisher": "Mathrubhumi Books",
        "works": [
            {"title": "Magdalana Mariam", "year": 1921},
            {"title": "Sahitya Manjari", "year": 1917},
        ],
    },
    {
        "name": "Ulloor S. Parameswara Iyer",
        "pen_name": None,
        "publisher": "National Book Stall",
        "works": [{"title": "Umakeralam", "year": 1913}],
    },
    {
        "name": "G. Sankara Kurup",
        "pen_name": None,
        "publisher": "Mathrubhumi Books",
        "works": [
            {"title": "Odakkuzhal", "year": 1950},
            {"title": "Viswadarshanam", "year": 1960},
        ],
    },
    {
        "name": "Changampuzha Krishna Pillai",
        "pen_name": None,
        "publisher": "National Book Stall",
        "works": [{"title": "Ramanan", "year": 1936}],
    },
    {
        "name": "Vyloppilli Sreedhara Menon",
        "pen_name": None,
        "publisher": "Mathrubhumi Books",
        "works": [
            {"title": "Kanneerpaadam", "year": 1948},
            {"title": "Sahyante Makan", "year": 1962},
        ],
    },
    {
        "name": "O.N.V. Kurup",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Ujjayini", "year": 1997},
            {"title": "Bhoomikkoru Charamageetham", "year": 1984},
        ],
    },
    {
        "name": "Sugathakumari",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Rathrimazha", "year": 1977},
            {"title": "Manalezhuthu", "year": 2004},
        ],
    },
    {
        "name": "Edasseri Govindan Nair",
        "pen_name": None,
        "publisher": "Mathrubhumi Books",
        "works": [{"title": "Kuttippuram Palam", "year": 1954}],
    },
    {
        "name": "Akkitham Achuthan Namboothiri",
        "pen_name": None,
        "publisher": "Current Books",
        "works": [{"title": "Irupatham Noottandinte Ithihasam", "year": 1952}],
    },
    {
        "name": "Balamani Amma",
        "pen_name": None,
        "publisher": "Mathrubhumi Books",
        "works": [
            {"title": "Amma", "year": 1934},
            {"title": "Muthassi", "year": 1962},
        ],
    },
    {
        "name": "V.K.N.",
        "pen_name": "Vadakke Koottala Narayanankutty Nair",
        "publisher": "DC Books",
        "works": [
            {"title": "Pitamahan", "year": 1978},
            {"title": "Payyan Kathakal", "year": 1980},
        ],
    },
    {
        "name": "Madampu Kunjukuttan",
        "pen_name": None,
        "publisher": "DC Books",
        "works": [
            {"title": "Bhrashtu", "year": 1969},
            {"title": "Ashwathama", "year": 1978},
        ],
    },
]
