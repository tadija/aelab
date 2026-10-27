"""Checks for the explicit API contract and its embedded server copy."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('api_docs', ROOT/'Scripts/generate-api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class APIDocumentTests(unittest.TestCase):
    def setUp(self):
        self.document = json.loads((ROOT/'Docs/openapi.json').read_text())
        source = '\n'.join(path.read_text() for path in (ROOT/'Sources/Server').glob('*.swift') if path.name != 'APIDocument.swift')
        self.routes = api.routes(source)

    def test_current_document_covers_routes_and_embedded_copy(self):
        api.validate(self.document, self.routes)
        self.assertEqual(api.render(self.document), (ROOT/'Sources/Server/APIDocument.swift').read_text())

    def test_embedded_api_uses_the_release_version(self):
        source = api.render(self.document)
        self.assertIn('\\#(AelabVersion.current)', source)
        self.assertEqual(self.document['info']['version'], 'VERSION')
        self.assertIn('\\#(AelabVersion.build)', source)
        self.assertEqual(self.document['info']['x-build'], 'BUILD')

    def test_missing_and_obsolete_endpoints_are_rejected(self):
        for changed in [self.routes | {('get', '/api/missing')}, self.routes - {('get', '/api/config')}]:
            with self.assertRaisesRegex(ValueError, 'route coverage'):
                api.validate(self.document, changed)

    def test_invalid_schema_reference_is_rejected(self):
        self.document['components']['schemas']['Broken'] = {'$ref': '#/components/schemas/Missing'}
        with self.assertRaisesRegex(ValueError, 'Unknown reference'):
            api.validate(self.document, self.routes)

    def test_duplicate_operations_and_routes_are_rejected(self):
        self.document['paths']['/api/config']['get']['operationId'] = self.document['paths']['/health']['get']['operationId']
        with self.assertRaisesRegex(ValueError, 'Duplicate operationId'):
            api.validate(self.document, self.routes)
        with self.assertRaisesRegex(ValueError, 'Duplicate HTTP routes'):
            api.routes('router.get("/api/config") {}\nrouter.get("/api/config") {}')

    def test_required_path_parameters_are_checked(self):
        operation = self.document['paths']['/api/hosts/{host}/status']['get']
        operation['parameters'] = []
        with self.assertRaisesRegex(ValueError, 'Path parameters differ'):
            api.validate(self.document, self.routes)

    def test_output_is_alphabetical_regardless_of_input_order(self):
        reordered = copy.deepcopy(self.document)
        reordered['paths'] = dict(reversed(list(reordered['paths'].items())))
        for operations in reordered['paths'].values():
            values = list(operations.items())
            operations.clear()
            operations.update(reversed(values))
        self.assertEqual(api.render(reordered), api.render(self.document))


if __name__ == '__main__':
    unittest.main()
