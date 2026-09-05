from kivy.uix.color import Color
from kivy.uix.rectangle import Rectangle
from kivy.uix.widget import Widget


class TestCanvas(Widget):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._bindings = []
        color_B6BF02D5 = Color(rgb=(1.0, 0.0, 0.0))
        self.add_widget(color_B6BF02D5)
        rectangle_F3A37B9D = Rectangle()
        rectangle_F3A37B9D.pos = self.pos
        self.bind(pos=rectangle_F3A37B9D.setter("pos"))
        rectangle_F3A37B9D.size = self.size
        self.bind(size=rectangle_F3A37B9D.setter("size"))
        self.add_widget(rectangle_F3A37B9D)

    def __del__(self):
        for (obj, prop, callback) in self._bindings:
            try:
                obj.unbind(**{prop: callback})
            except:
                pass