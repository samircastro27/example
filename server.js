
const express = require('express');
const app = express();
const path = require('path');

require('dotenv').config();

app.get("/", function(req, res){
    res.sendFile(path.join(__dirname+'/index.html'));
});

app.get("/saludos", function(req, res){
    res.send("Hola desde express");
});

const PORT = process.env.PORT || 8000

app.listen(PORT, ()=> {
    console.log(`El servidor funciona correctamente en el puerto: ${PORT}`);
})
