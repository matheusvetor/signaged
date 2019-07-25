var casper = require('casper').create();
var username = '00713105';
var password = 'ac83fba4';

casper.start('http://tvopen.com.br', function() {
  this.echo(this.getTitle());
});

casper.then(function() {
  casper.wait(5000, function(){
    this.echo(this.getTitle());
    if (this.exists('form#formaut')) {
      this.echo('formulário existe');
      casper.wait(5000);
      this.sendKeys('input[name="username"]', username);
      this.sendKeys('input[name="password"]', password);
      this.click('form#formaut button');
    };
  });
});

casper.run();
