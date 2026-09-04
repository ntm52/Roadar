import unittest
from build_offline_roads import speed, directions

class RoadTagsTests(unittest.TestCase):
    def test_units_and_explicit_direction_override(self):
        self.assertEqual(speed({'maxspeed': '35 mph'}, 'forward'), '35 mph')
        self.assertEqual(speed({'maxspeed': '50'}, 'forward'), '50 km/h')
        self.assertEqual(speed({'maxspeed': '35 mph', 'maxspeed:backward': '25 mph'}, 'backward'), '25 mph')
        self.assertIsNone(speed({'maxspeed': '35 mph', 'maxspeed:forward': 'signals'}, 'forward'))

    def test_unknown_and_conditional_limits_are_withheld(self):
        for value in ['', 'none', 'signals', 'US:urban', '25;35', '999 mph']:
            self.assertIsNone(speed({'maxspeed': value}, 'forward'))
        for key in ['maxspeed:conditional', 'maxspeed:lanes', 'maxspeed:variable']:
            self.assertIsNone(speed({'maxspeed': '35 mph', key: '25 @ school'}, 'forward'))

    def test_travel_direction(self):
        for value, expected in [('yes',1),('-1',-1),('no',2),('reversible',0)]:
            self.assertEqual(directions({'oneway':value}), expected)
        self.assertEqual(directions({'junction':'roundabout'}),1)
        self.assertEqual(directions({'junction':'roundabout','oneway':'no'}),2)
        self.assertEqual(directions({'highway':'motorway'}),1)
        self.assertEqual(directions({'oneway':'yes','oneway:conditional':'no @ evening'}),0)

if __name__ == '__main__': unittest.main()
