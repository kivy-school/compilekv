from kivy.uix.widget import Widget
from kivy.graphics import Ellipse


class TestBinding(Widget):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._bindings = []
        self._canvas_ellipse_81F886DC = Ellipse(size=(40.0, 40.0))
        self.canvas.add(self._canvas_ellipse_81F886DC)
        self._canvas_ellipse_81F886DC.pos = ((self.center_x - 20), (self.center_y - 20))
        _callback_1 = lambda instance, value: setattr(self._canvas_ellipse_81F886DC, "pos", ((instance.center_x - 20), (instance.center_y - 20)))
        self.bind(center_x=_callback_1)
        _callback_2 = lambda instance, value: setattr(self._canvas_ellipse_81F886DC, "pos", ((instance.center_x - 20), (instance.center_y - 20)))
        self.bind(center_y=_callback_2)
        self._bindings.append((self, "center_x", _callback_1))
        self._bindings.append((self, "center_y", _callback_2))

    def __del__(self):
        for (obj, prop, callback) in self._bindings:
            try:
                obj.unbind(**{prop: callback})
            except:
                pass