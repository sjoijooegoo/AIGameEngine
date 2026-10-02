"""Run asset checks and optionally create actual engine-rendered preview evidence."""
import argparse
import json
import sys
import time
import unittest
from lab import ROOT, atomic_json
from asset_library import preview_asset, digest, inspect_asset
from scene_pipeline import preview_scene


class EvidenceResult(unittest.TextTestResult):
    checks=[]
    def addSuccess(self,test):
        super().addSuccess(test)
        self.checks.append({'name':test._testMethodName,'status':'pass'})
    def addFailure(self,test,error):
        super().addFailure(test,error)
        self.checks.append({'name':test._testMethodName,'status':'fail','error':str(error[1])})
    def addError(self,test,error):
        super().addError(test,error)
        self.checks.append({'name':str(test),'status':'fail','error':str(error[1])})
    def addSubTest(self,test,subtest,error):
        super().addSubTest(test,subtest,error)
        if error:self.checks.append({'name':test._testMethodName,'status':'fail','error':str(error[1])})


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--headless',action='store_true')
    args=parser.parse_args()
    folder=ROOT/'artifacts'/('asset-qa-'+time.strftime('%Y%m%d-%H%M%S'));folder.mkdir(parents=True)
    suite=unittest.defaultTestLoader.discover(str(ROOT/'tests'),pattern='test_asset_pipeline.py')
    result=unittest.TextTestRunner(verbosity=2,resultclass=EvidenceResult).run(suite)
    report={'checks':result.checks,'previews':[],'headless':args.headless,'visual_review':'not_reviewed'}
    if result.wasSuccessful() and not args.headless:
        for asset,lighting in [('demo.counter','neutral'),('qa.chair_fbx','raking'),('demo.terminal','dark'),('demo.wood','neutral')]:
            preview=preview_asset(asset,lighting)
            if 'bounds' in preview:
                expected=inspect_asset(asset)['prepared']['measured']['size_m']
                if any(abs(a-b)>0.001 for a,b in zip(preview['bounds']['size'],expected)):
                    raise AssertionError('Preview bounds differ from measured asset: '+asset)
            report['previews'].append(preview)
        report['previews'].append(preview_scene('bank_room'))
        for preview in report['previews']:
            preview['contact_sha256']=digest(preview['contact_sheet'])
    atomic_json(folder/'report.json',report)
    print(json.dumps({'report':str(folder/'report.json'),'passed':result.wasSuccessful(),'checks':len(report['checks']),'previews':len(report['previews'])}))
    return 0 if result.wasSuccessful() else 1


if __name__=='__main__':sys.exit(main())
