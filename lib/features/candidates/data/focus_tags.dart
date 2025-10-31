const kGovernmentLevels = <String>[
  'All levels',
  'Federal',
  'State',
  'County',
  'City/Township',
];

const kFocusAreaTags = <String, List<Map<String, String>>>{
  'Cost of living': <Map<String, String>>[
    {'Affordable housing': 'affordable-housing'},
    {'Healthcare': 'healthcare'},
    {'Labor rights': 'labor-rights'},
  ],
  'Environmental': <Map<String, String>>[
    {'Clean water': 'clean-water'},
    {'Climate action': 'climate-action'},
    {'Public lands': 'public-lands'},
  ],
  'Families & education': <Map<String, String>>[
    {'Early childhood': 'early-childhood'},
    {'K-12': 'k12'},
    {'Higher ed': 'higher-education'},
  ],
  'Community & justice': <Map<String, String>>[
    {'Public safety': 'public-safety'},
    {'Voting rights': 'voting-rights'},
    {'Criminal justice': 'criminal-justice'},
  ],
  'Infrastructure & growth': <Map<String, String>>[
    {'Transit': 'transit'},
    {'Broadband': 'broadband'},
    {'Small business': 'small-business'},
  ],
};
