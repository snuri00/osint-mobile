const List<Map<String, dynamic>> kToolDefs = [
  {
    'name': 'search_news',
    'description':
        'Search a curated registry of ~525 RSS feeds for a topic/keyword and return '
            'ranked, deduplicated headlines, each flagged with its source tier and any '
            'propaganda-risk / state-affiliation. Keyless. Use for event/journalist-style '
            'news intelligence, not for a person. For Turkey-specific questions or the '
            "Turkish agenda (\"Türkiye gündemi\"), pass category='turkey' to search ~27 "
            'Turkish outlets (Anadolu Ajansı, TRT, Hürriyet, Sözcü, Cumhuriyet, BBC Türkçe, '
            'etc.). For a general agenda overview with no specific topic, set the matching '
            'category and pass a short/empty query — you will get the latest headlines.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Topic or keywords to search. May be empty for a general agenda overview when a category is set.'},
        'category': {
          'type': 'string',
          'description':
              "Optional feed category/region: 'turkey' (Turkish sources), 'middleeast', 'energy', 'gov', etc., or a variant ('world','tech','finance','commodity','intel').",
        },
      },
      'required': ['query'],
    },
  },
  {
    'name': 'search_events',
    'description':
        'Query GDELT for global news coverage of a topic/place/event: recent articles '
            'plus aggregate volume and which source countries and outlets are reporting. '
            "Keyless. Best for 'what is being reported worldwide and where'.",
    'input_schema': {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Topic, place, person, or event keywords.'},
        'timespan': {
          'type': 'string',
          'description': "Rolling window, e.g. '24h', '3d', '7d'. Default 7d.",
        },
      },
      'required': ['query'],
    },
  },
  {
    'name': 'search_disasters',
    'description':
        'Aggregate recent natural-disaster events from USGS earthquakes, GDACS alerts, '
            'and NASA EONET (wildfires, storms, volcanoes, floods). Keyless. Optional region '
            'keyword filter.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'region': {
          'type': 'string',
          'description': "Optional region/country keyword to filter (e.g. 'Turkey', 'Japan').",
        },
      },
      'required': [],
    },
  },
  {
    'name': 'search_reliefweb',
    'description':
        'Query ReliefWeb (UN OCHA) for the latest humanitarian situation reports and '
            'disaster coverage for a country or topic. Keyless.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': "Country or topic (e.g. 'Sudan', 'Gaza')."},
      },
      'required': ['query'],
    },
  },
  {
    'name': 'monitor_country',
    'description':
        'Build a multi-source situational brief for a country/region: curated news, '
            'GDELT event coverage, natural-disaster alerts, and UN humanitarian reporting '
            'in one call. Keyless. Use this first for a country-level situational question.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'country': {'type': 'string', 'description': 'Country or region name.'},
      },
      'required': ['country'],
    },
  },
];
