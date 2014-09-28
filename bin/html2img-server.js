var phantom = require('phantom');
var temp = require('temp');
var http = require('http');
var fs = require('fs');
var url = require('url');

temp.track();

var working_path = process.argv[2];
if (!working_path) {
  console.log("Usage: node html2img-server.js [WORKING_PATH]");
  process.exit(1);
}

phantom.create(function(ph) {
  function render_html(file_path, opts, cb) {
    var tmp_filename = temp.path({suffix: '.png'});

    ph.createPage(function(page) {
      page.open('file://' + file_path, function() {
        page.setViewportSize(1920, 1080, function() {
          page.clipRect = {
            top: 0,
            left: 0,
            width: 1920,
            height: 1080
          };
          page.render(tmp_filename, opts, function() { cb(tmp_filename); });
        });
      });
    });
  }

  function app(req, res) {
    var url_parts = url.parse(req.url, true);
    var file_path = working_path + url_parts.query.file_path;

    render_html(file_path, {}, function(rendered_filename) {
      fs.readFile(rendered_filename, function (err, data) {
        if (err) {
          res.writeHead(500);
          res.end(err.toString());
        } else {
          res.writeHead(200, {
              'Content-Length': data.length,
              'Content-Type': 'image/png'
          });
          res.end(data);
        }
      });
    });
  }

  http.createServer(app).listen(3000);
  console.log(process.argv[1] + ': Working path: ' + working_path);
  console.log(process.argv[1] + ': Server listening on port 3000...');
});
