# Snipstep screenshots

The walkthrough uses [the public Ponytail repository](https://github.com/DietrichGebert/ponytail) as the example task. The first panel places a cropped screenshot of that page alongside a render of Snipstep’s native list with sample tasks. The detail and desktop-widget images are cropped from real screenshots supplied by the creator.

Ponytail is by Dietrich Gebert and its contributors. GitHub’s interface and the content shown from Ponytail retain their respective ownership. The desktop background visible through the app and widget uses Albert Bierstadt’s [Looking Down Yosemite Valley, California](https://www.artsbma.org/collection/looking-down-yosemite-valley-california/).

To render sample panels with Xcode and Python 3, supply a PNG cropped to a public webpage.

```sh
bash scripts/make-demo.sh /path/to/public-page.png
```

The renderer uses an in-memory database and temporary attachments and preferences. It does not read the installed library, use stored credentials, or send the screenshot to a cloud API.
