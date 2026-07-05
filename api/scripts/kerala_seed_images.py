"""Author portraits and publisher marks for the Kerala seed, fetched from the
Wikipedia/Wikimedia REST API (real upload.wikimedia.org URLs, not fabricated).
Keys match the names in `kerala_seed.py`. Merged in by `seed_catalog.py`."""

AUTHOR_IMAGES: dict[str, str | None] = {
    "Thakazhi Sivasankara Pillai": "https://upload.wikimedia.org/wikipedia/commons/d/dc/Thakazhi_1.jpg",
    "Vaikom Muhammad Basheer": "https://upload.wikimedia.org/wikipedia/commons/f/f0/Vaikom_Muhammad_Basheer_2009_stamp_of_India.jpg",
    "O.V. Vijayan": "https://upload.wikimedia.org/wikipedia/commons/d/d4/Vijayan.jpg",
    "M.T. Vasudevan Nair": "https://upload.wikimedia.org/wikipedia/commons/thumb/2/26/MT_Vasudevan_Nair.jpg/3840px-MT_Vasudevan_Nair.jpg",
    "Kamala Das": "https://upload.wikimedia.org/wikipedia/commons/b/b3/Kamala_das.jpg",
    "S.K. Pottekkatt": "https://upload.wikimedia.org/wikipedia/commons/d/df/S._K._Pottekkatt.jpg",
    "Lalithambika Antharjanam": "https://upload.wikimedia.org/wikipedia/en/c/c2/Lalithambika_Antherjanam.jpg",
    "P. Kesava Dev": "https://upload.wikimedia.org/wikipedia/commons/a/af/Kesavadev.jpg",
    "Uroob": "https://upload.wikimedia.org/wikipedia/commons/9/94/Uroob.jpg",
    "M. Mukundan": "https://upload.wikimedia.org/wikipedia/commons/8/84/Book_release_by_mukundan26.jpg",
    "Anand": "https://upload.wikimedia.org/wikipedia/commons/5/57/Anand_p_sachidanandan-2.jpg",
    "Punathil Kunjabdulla": "https://upload.wikimedia.org/wikipedia/commons/f/f2/Punathil_W.jpg",
    "Malayattoor Ramakrishnan": "https://upload.wikimedia.org/wikipedia/en/7/76/Malayattoor_Ramakrishnan.jpg",
    "C.V. Raman Pillai": "https://upload.wikimedia.org/wikipedia/commons/0/05/CVs60thbirthday.png",
    "Sara Joseph": "https://upload.wikimedia.org/wikipedia/commons/5/57/Sara_Joseph_-_Malayalam_Writer_and_Activist.jpg",
    "K.R. Meera": "https://upload.wikimedia.org/wikipedia/commons/a/a6/KR_Meera_KLF-2016.JPG",
    "Benyamin": "https://upload.wikimedia.org/wikipedia/commons/thumb/6/66/Benyamin_Writer.jpg/3840px-Benyamin_Writer.jpg",
    "Perumbadavam Sreedharan": "https://upload.wikimedia.org/wikipedia/commons/3/32/Perumbadavam.jpg",
    "T. Padmanabhan": "https://upload.wikimedia.org/wikipedia/commons/4/4e/T_Padmanabhan_closeup.JPG",
    "Paul Zacharia": "https://upload.wikimedia.org/wikipedia/commons/thumb/d/df/Paul_zacharia_at_Kollam_2025_1.jpg/3840px-Paul_zacharia_at_Kollam_2025_1.jpg",
    "N.S. Madhavan": "https://upload.wikimedia.org/wikipedia/commons/5/5d/%E0%B4%8E%E0%B4%A8%E0%B5%8D%E2%80%8D.%E0%B4%8E%E0%B4%B8%E0%B5%8D_%E0%B4%AE%E0%B4%BE%E0%B4%A7%E0%B4%B5%E0%B4%A8%E0%B5%8D%E2%80%8D.jpg",
    "Subhash Chandran": "https://upload.wikimedia.org/wikipedia/commons/9/95/Subhash_Chandran.jpg",
    "Kovilan": "https://upload.wikimedia.org/wikipedia/commons/2/25/Kovilan.jpeg",
    "Kakkanadan": "https://upload.wikimedia.org/wikipedia/commons/6/66/Kakkanadan3_-kakka-.JPG",
    "O. Chandu Menon": "https://upload.wikimedia.org/wikipedia/en/d/d1/Chandu_Menon.jpg",
    "Kumaran Asan": "https://upload.wikimedia.org/wikipedia/commons/5/55/Kumaran_Asan_1973_stamp_of_India.jpg",
    "Vallathol Narayana Menon": "https://upload.wikimedia.org/wikipedia/commons/0/00/Vallathol_Narayana_Menon_2.jpg",
    "Ulloor S. Parameswara Iyer": "https://upload.wikimedia.org/wikipedia/commons/b/b4/Ulloor_S._Parameswara_Iyer_1936.jpg",
    "G. Sankara Kurup": "https://upload.wikimedia.org/wikipedia/commons/8/86/G.shankarakurup.jpg",
    "Changampuzha Krishna Pillai": "https://upload.wikimedia.org/wikipedia/commons/6/63/Changampuzha.jpg",
    "Vyloppilli Sreedhara Menon": "https://upload.wikimedia.org/wikipedia/commons/8/8d/Vyloppilli.jpg",
    "O.N.V. Kurup": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/ONV_DSC_0118.A.JPG/500px-ONV_DSC_0118.A.JPG",
    "Sugathakumari": "https://upload.wikimedia.org/wikipedia/commons/9/91/Sugathakumari.jpg",
    "Edasseri Govindan Nair": "https://upload.wikimedia.org/wikipedia/commons/1/1f/Edasseri_Govindan_Nair.jpg",
    "Akkitham Achuthan Namboothiri": "https://upload.wikimedia.org/wikipedia/commons/0/09/Akkitham_Achuthan_Namboothiri_.jpg",
    "Balamani Amma": "https://upload.wikimedia.org/wikipedia/commons/7/72/Balamaniamma.jpg",
    "V.K.N.": "https://upload.wikimedia.org/wikipedia/en/4/4f/Writer_VKN.jpg",
    "Madampu Kunjukuttan": "https://upload.wikimedia.org/wikipedia/commons/2/2e/Madampu_Kunjukuttan_IMG_9615.jpg",
}

PUBLISHER_LOGOS: dict[str, str | None] = {
    "DC Books": "https://upload.wikimedia.org/wikipedia/commons/e/e7/Dc_logo_updated.png",
    "Manorama Books": "https://upload.wikimedia.org/wikipedia/commons/6/6f/Malayalamanorama.png",
}
