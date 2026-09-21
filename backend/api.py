from flask import Flask, request, send_file
import io
from app import flawless_exact_tick_injection

app = Flask(__name__)

@app.route('/stamp', methods=['POST'])
def stamp_pdf():
    if 'pdf' not in request.files:
        return {'error': 'No PDF file'}, 400
    
    pdf_file = request.files['pdf']
    password = request.form.get('password', '')
    
    try:
        result = flawless_exact_tick_injection(
            pdf_file.read(), 
            password=password
        )
        
        if result:
            return send_file(
                io.BytesIO(result),
                mimetype='application/pdf',
                as_attachment=True,
                download_name='stamped.pdf'
            )
        else:
            return {'error': 'No signature field found'}, 404
            
    except Exception as e:
        return {'error': str(e)}, 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
